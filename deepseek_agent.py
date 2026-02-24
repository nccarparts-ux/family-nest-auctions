import os
import subprocess
import time
import re
import json
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
        
        # NEW: Memory system
        self.memory_file = os.path.join(self.project_root, ".ai_memory.json")
        self.conversation_history = []
        self.modified_files_history = []
        self.load_memory()

    # =============================
    # MEMORY SYSTEM (NEW)
    # =============================
    def load_memory(self):
        """Load previous session memory"""
        if os.path.exists(self.memory_file):
            try:
                with open(self.memory_file, 'r') as f:
                    memory = json.load(f)
                    self.modified_files_history = memory.get('modified_files', [])
                    self.conversation_history = memory.get('conversation', [])
                print(f"📚 Loaded memory: Previously modified {len(self.modified_files_history)} files")
            except:
                print("⚠️ Could not load memory file")

    def save_memory(self):
        """Save session memory"""
        memory = {
            'modified_files': self.modified_files_history,
            'conversation': self.conversation_history[-10:],  # Keep last 10 exchanges
            'last_session': datetime.now().isoformat()
        }
        with open(self.memory_file, 'w') as f:
            json.dump(memory, f, indent=2)

    def add_to_memory(self, role, content):
        """Add a conversation to memory"""
        self.conversation_history.append({
            'role': role,
            'content': content,
            'timestamp': datetime.now().isoformat()
        })
        # Keep memory manageable
        if len(self.conversation_history) > 20:
            self.conversation_history = self.conversation_history[-20:]
        self.save_memory()

    def get_memory_context(self):
        """Generate context string from memory"""
        if not self.conversation_history:
            return "No previous session history."
        
        context = "\n📋 PREVIOUS SESSION HISTORY:\n"
        for entry in self.conversation_history[-5:]:  # Last 5 exchanges
            context += f"[{entry['role']}]: {entry['content'][:100]}...\n"
        
        if self.modified_files_history:
            context += f"\n📁 Previously modified files: {', '.join(self.modified_files_history[-10:])}\n"
        
        return context

    # =============================
    # FILE LIST
    # =============================
    def list_project_files(self):
        file_list = []

        for root, dirs, files in os.walk(self.project_root):
            if any(x in root for x in [".git", "node_modules", "__pycache__"]):
                continue

            for file in files:
                if file.endswith((".html", ".js", ".css", ".json", ".py")):
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
    # SAFE COMPLETION
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
                        time.sleep(1)
                    else:
                        print(f"\n✅ Response complete ({continuation_count + 1} parts)")
                        bar()
                        break

                except Exception as e:
                    print(f"\n❌ Error during completion: {e}")
                    import traceback
                    traceback.print_exc()
                    break

        # Add to memory
        self.add_to_memory("assistant", full_content[:500])
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

        # Update memory with modified files
        self.modified_files_history.extend(changed_files)
        self.save_memory()

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
            return True
        except subprocess.CalledProcessError as e:
            print(f"❌ Push failed: {e.stderr}")
            
            # Check if it's a secret scanning issue
            if "secret" in e.stderr.lower():
                print("\n🔐 GitHub detected a secret in your code!")
                print("This is a security feature to protect your credentials.")
                print("\nTo fix this:")
                print("1. Remove the secret from the file")
                print("2. Use environment variables instead")
                print("3. Or visit the URL in the error to allow the secret")
            return False

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
    # MAIN (NOW WITH LOOP)
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
        print("✅ REMEMBER previous sessions")
        print("="*60)
        
        # Show memory from previous session
        memory_context = self.get_memory_context()
        if "No previous session" not in memory_context:
            print(memory_context)
            print("="*60)

        while True:  # MAIN LOOP - stays in bot
            try:
                user_input = input("\n📋 What would you like to change? (or 'exit' to quit, 'status' to see changes, 'push' to retry push)\n> ")

                if user_input.lower() == 'exit':
                    self.save_memory()
                    print("👋 Goodbye! Memory saved for next session.")
                    break

                if user_input.lower() == 'status':
                    print(f"\n📁 Modified files this session: {', '.join(self.modified_files_history[-10:])}")
                    continue

                if user_input.lower() == 'push':
                    print("🚀 Retrying push...")
                    self.push_branch()
                    continue

                # Add user input to memory
                self.add_to_memory("user", user_input)

                print("\n🔍 Scanning project files...")
                file_list = self.list_project_files()
                print(f"📁 Found {len(file_list)} relevant files")

                selector_prompt = f"""
You are an expert code reviewer. Based on the user's request, identify which files need to be modified.

{self.get_memory_context()}

Current request: {user_input}

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
                    continue

                # Verify files exist
                valid_files = []
                for f in selected_files:
                    if os.path.exists(os.path.join(self.project_root, f)):
                        valid_files.append(f)
                    else:
                        print(f"⚠️ File not found: {f}")

                if not valid_files:
                    print("❌ None of the identified files exist.")
                    continue

                print(f"\n📚 Loading {len(valid_files)} files for context...")
                context = self.load_selected_files(valid_files)

                modification_prompt = f"""
You are an expert web developer. Modify the provided files to fulfill this request:

USER REQUEST: {user_input}

PREVIOUS CHANGES: {', '.join(self.modified_files_history[-5:]) if self.modified_files_history else 'None'}

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
                    continue

                print(f"\n✅ Successfully modified {len(changed_files)} files:")
                for f in changed_files:
                    print(f"  • {f}")

                # Git operations
                print("\n📌 Staging changes...")
                subprocess.run(["git", "add", "."], check=True, capture_output=True)

                commit_message = f"AI Update: {user_input[:50]}..."
                print(f"💾 Committing: {commit_message}")
                subprocess.run(["git", "commit", "-m", commit_message], check=True, capture_output=True)

                print("🚀 Attempting to push to GitHub...")
                push_success = self.push_branch()

                if not push_success:
                    print("\n⚠️ Push failed due to security rules.")
                    print("You can:")
                    print("  - Type 'push' to retry after fixing the issue")
                    print("  - Fix the secret in the file and try again")
                    print("  - Continue with other tasks and push later")

                # Try to create PR (optional)
                self.create_pull_request()

                print("\n" + "="*60)
                print("✅ Task completed! You can continue with another task.")
                print("="*60)

            except KeyboardInterrupt:
                print("\n\n👋 Interrupted. Saving memory...")
                self.save_memory()
                break
            except Exception as e:
                print(f"\n❌ Unexpected error: {e}")
                import traceback
                traceback.print_exc()
                print("\nContinuing...")

if __name__ == "__main__":
    agent = DeepSeekAgent()
    agent.run()