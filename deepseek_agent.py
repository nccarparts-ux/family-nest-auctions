import os
import subprocess
import time
import re
from datetime import datetime
from deepseek import DeepSeekAPI
from dotenv import load_dotenv
from alive_progress import alive_bar

load_dotenv()


class DeepSeekAgent:

    def __init__(self):
        self.api = DeepSeekAPI(api_key=os.getenv("DEEPSEEK_API_KEY"))
        self.project_root = os.getcwd()
        self.max_continuations = 6
        self.branch_name = f"ai-update-{int(time.time())}"

    # =============================
    # FILE LIST
    # =============================
    def list_project_files(self):
        file_list = []

        for root, dirs, files in os.walk(self.project_root):
            if any(x in root for x in [".git", "node_modules", "__pycache__"]):
                continue

            for file in files:
                if file.endswith((".html", ".js", ".css", ".json")):
                    relative_path = os.path.relpath(
                        os.path.join(root, file),
                        self.project_root
                    )
                    file_list.append(relative_path)

        return file_list

    # =============================
    # LOAD SELECTED FILES
    # =============================
    def load_selected_files(self, selected_files):

        context = ""

        for file_path in selected_files:
            full_path = os.path.join(self.project_root, file_path)

            if os.path.exists(full_path):
                with open(full_path, "r", encoding="utf-8") as f:
                    content = f.read()

                # Large file protection
                if len(content) > 15000:
                    content = content[:15000]

                context += f"\nFILE: {file_path}\n{content}\n"

        return context

    # =============================
    # SAFE COMPLETION (FIXED)
    # =============================
    def get_completion(self, messages):
        """Get completion from DeepSeek with automatic continuation"""
        print(f"📤 Sending {len(messages)} messages to DeepSeek...")
        full_content = ""
        continuation_count = 0
        current_messages = messages.copy()

        with alive_bar(self.max_continuations + 1, title="🤖 DeepSeek", spinner="dots_waves") as bar:

            while continuation_count < self.max_continuations:

                try:
                    response = self.api.chat_completion(
                        messages=current_messages,
                        stream=False,
                    )

                    # Handle different response formats
                    if isinstance(response, dict) and "choices" in response:
                        # Dictionary response
                        choice = response["choices"][0]
                        content = choice["message"]["content"]
                        finish_reason = choice.get("finish_reason", "stop")
                    elif hasattr(response, 'choices'):
                        # Object response
                        choice = response.choices[0]
                        content = choice.message.content
                        finish_reason = getattr(choice, 'finish_reason', 'stop')
                    else:
                        # String response
                        content = str(response)
                        finish_reason = 'stop'

                    if continuation_count == 0:
                        print(f"\n📝 Response preview: {content[:200]}...\n")

                    full_content += content

                    if finish_reason == "length":
                        print(f"\n⏳ Response truncated. Getting continuation {continuation_count + 2}...")
                        current_messages.append({
                            "role": "assistant",
                            "content": content
                        })
                        current_messages.append({
                            "role": "user",
                            "content": "Continue EXACTLY where you stopped."
                        })
                        continuation_count += 1
                        bar()
                        time.sleep(1)  # Small delay to avoid rate limits
                    else:
                        print(f"\n✅ Response complete ({continuation_count + 1} parts)")
                        bar()
                        break

                except Exception as e:
                    print(f"\n❌ Error during completion: {e}")
                    import traceback
                    traceback.print_exc()
                    break

        return full_content

    # =============================
    # APPLY PATCHES
    # =============================
    def apply_patches(self, response_text):

        patch_pattern = r"\[PATCH\](.*?)\[\/PATCH\]"
        write_pattern = r"\[WRITE\](.*?)\[\/WRITE\]"

        patch_blocks = re.findall(patch_pattern, response_text, re.DOTALL)
        write_blocks = re.findall(write_pattern, response_text, re.DOTALL)

        changed_files = []

        # ---- PATCH HANDLING ----
        for block in patch_blocks:

            path = re.search(r"\[PATH\](.*?)\[\/PATH\]", block)
            search = re.search(r"\[SEARCH\](.*?)\[\/SEARCH\]", block, re.DOTALL)
            replace = re.search(r"\[REPLACE\](.*?)\[\/REPLACE\]", block, re.DOTALL)

            if not path or not search or not replace:
                continue

            file_path = path.group(1).strip()
            full_path = os.path.join(self.project_root, file_path)

            if not os.path.exists(full_path):
                print(f"⚠️ File not found: {file_path}")
                continue

            with open(full_path, "r", encoding="utf-8") as f:
                content = f.read()

            search_text = search.group(1).strip()
            replace_text = replace.group(1).strip()

            if search_text in content:
                content = content.replace(search_text, replace_text)

                with open(full_path, "w", encoding="utf-8") as f:
                    f.write(content)

                print(f"🔧 Patched: {file_path}")
                changed_files.append(file_path)
            else:
                print(f"⚠️ Search text not found in {file_path}")

        # ---- FULL WRITE HANDLING ----
        for block in write_blocks:

            path = re.search(r"\[PATH\](.*?)\[\/PATH\]", block)
            content = re.search(r"\[CONTENT\](.*?)\[\/CONTENT\]", block, re.DOTALL)

            if not path or not content:
                continue

            file_path = path.group(1).strip()
            full_path = os.path.join(self.project_root, file_path)

            # Create backup
            if os.path.exists(full_path):
                backup_path = full_path + '.backup'
                import shutil
                shutil.copy2(full_path, backup_path)
                print(f"📦 Backup created: {backup_path}")

            # Create directories if needed
            os.makedirs(os.path.dirname(full_path), exist_ok=True)

            with open(full_path, "w", encoding="utf-8") as f:
                f.write(content.group(1).strip())

            print(f"📝 Rewritten: {file_path}")
            changed_files.append(file_path)

        return changed_files

    # =============================
    # GIT WORKFLOW
    # =============================
    def create_branch(self):
        try:
            subprocess.run(["git", "checkout", "-b", self.branch_name], check=True, capture_output=True)
            print(f"🌿 Created branch: {self.branch_name}")
        except subprocess.CalledProcessError:
            # Branch might already exist
            subprocess.run(["git", "checkout", self.branch_name], check=True, capture_output=True)
            print(f"🌿 Switched to branch: {self.branch_name}")

    def push_branch(self):
        try:
            result = subprocess.run(
                ["git", "push", "-u", "origin", self.branch_name],
                check=True,
                capture_output=True,
                text=True
            )
            print(f"🚀 Pushed branch: {self.branch_name}")
            print(result.stdout)
        except subprocess.CalledProcessError as e:
            print(f"❌ Push failed: {e.stderr}")

    def create_pull_request(self):
        try:
            result = subprocess.run([
                "gh", "pr", "create",
                "--title", "AI Code Update",
                "--body", "Automated update via DeepSeek Agent",
                "--base", "main",
                "--head", self.branch_name
            ], check=True, capture_output=True, text=True)
            print(f"🚀 Pull request created: {result.stdout}")
        except subprocess.CalledProcessError:
            print("ℹ️ Install GitHub CLI (gh) to auto-create PRs.")
        except FileNotFoundError:
            print("ℹ️ GitHub CLI not installed. Install 'gh' for auto PR creation.")

    # =============================
    # MAIN
    # =============================
    def run(self):

        print("\n" + "="*60)
        print("🤖 DeepSeek Agent Ready!")
        print("="*60)
        print("This agent will:")
        print("✅ Read your project files")
        print("✅ Identify static/demo data")
        print("✅ Generate patches to fix them")
        print("✅ Apply changes automatically")
        print("✅ Create git branch & commit")
        print("✅ Push to GitHub")
        print("="*60)

        user_input = input("\nWhat would you like to change?\n> ")

        print("\n🔍 Scanning project files...")
        file_list = self.list_project_files()
        print(f"📁 Found {len(file_list)} relevant files")

        selector_prompt = """
You are an expert code reviewer. Based on the user's request, identify which files need to be modified.

Return ONLY a comma-separated list of filenames (relative paths) that must be edited.
No explanations, no markdown, just the filenames.

Example response: index.html,js/api.js,styles.css
"""

        print("\n🤖 Asking DeepSeek which files to modify...")
        selected = self.get_completion([
            {"role": "system", "content": selector_prompt},
            {"role": "user", "content": f"Project files:\n{chr(10).join(file_list[:50])}"},
            {"role": "user", "content": user_input}
        ])

        # Clean up the response
        selected = selected.replace("```", "").replace("csv", "").strip()
        print(f"\n📋 Files selected: {selected}")

        selected_files = [f.strip() for f in selected.split(",") if f.strip()]

        if not selected_files:
            print("❌ No relevant files identified.")
            return

        # Verify files exist
        valid_files = []
        for f in selected_files:
            if os.path.exists(os.path.join(self.project_root, f)):
                valid_files.append(f)
            else:
                print(f"⚠️ File not found: {f}")

        if not valid_files:
            print("❌ None of the identified files exist.")
            return

        print(f"\n📚 Loading {len(valid_files)} files for context...")
        context = self.load_selected_files(valid_files)

        modification_prompt = f"""
You are an expert web developer. Modify the provided files to fulfill this request:

USER REQUEST: {user_input}

IMPORTANT RULES:
1. Use PATCH blocks for small changes (search/replace)
2. Use WRITE blocks only for complete file rewrites
3. Always include the full file path
4. Make minimal changes necessary
5. Preserve all existing functionality

PATCH FORMAT:
[PATCH]
[PATH]relative/file/path.html[/PATH]
[SEARCH]
exact code to replace
[/SEARCH]
[REPLACE]
new code to insert
[/REPLACE]
[/PATCH]

WRITE FORMAT (use sparingly):
[WRITE]
[PATH]relative/file/path.html[/PATH]
[CONTENT]
complete new file content
[/CONTENT]
[/WRITE]

Return ONLY the patch/write blocks. No explanations.
"""

        print("\n🤖 Generating code changes...")
        response = self.get_completion([
            {"role": "system", "content": modification_prompt},
            {"role": "user", "content": context},
            {"role": "user", "content": "Generate the necessary patches to fulfill the user request."}
        ])

        # Create git branch
        print(f"\n🌿 Creating git branch: {self.branch_name}")
        self.create_branch()

        # Apply changes
        print("\n📝 Applying changes to files...")
        changed_files = self.apply_patches(response)

        if not changed_files:
            print("\n❌ No changes were applied.")
            print("This could mean:")
            print("  - The bot couldn't find the exact search text")
            print("  - The files are already correct")
            print("  - The response format was invalid")
            return

        print(f"\n✅ Successfully modified {len(changed_files)} files:")
        for f in changed_files:
            print(f"  • {f}")

        # Git operations
        print("\n📌 Staging changes...")
        subprocess.run(["git", "add", "."], check=True, capture_output=True)

        commit_message = f"AI Update: {user_input[:50]}..."
        print(f"💾 Committing: {commit_message}")
        subprocess.run(["git", "commit", "-m", commit_message], check=True, capture_output=True)

        print("🚀 Pushing to GitHub...")
        self.push_branch()

        # Try to create PR
        self.create_pull_request()

        print("\n" + "="*60)
        print("✅ All done! Check your GitHub repository for the new branch.")
        print("="*60)


if __name__ == "__main__":
    agent = DeepSeekAgent()
    agent.run()