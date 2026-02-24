from deepseek import DeepSeekAPI
import os
import sys
import time
import subprocess
import shlex

api_key = os.getenv("DEEPSEEK_API_KEY")
if not api_key:
    print("Please set DEEPSEEK_API_KEY first")
    print("Run: set DEEPSEEK_API_KEY=your_key_here")
    sys.exit(1)

api = DeepSeekAPI(api_key)

# Load context from file if it exists
context_file = "context.txt"
conversation_history = []
full_output_file = "complete_response.txt"

# Track files that have been modified
modified_files = []

if os.path.exists(context_file):
    print(f"Loading context from {context_file}...")
    with open(context_file, 'r', encoding='utf-8') as f:
        context = f.read()
    
    # Add context as a system message with instructions about file access
    system_message = f"""Here is the previous conversation history. Continue from this point:

{context}

IMPORTANT - YOU CAN NOW MODIFY FILES AND RUN GIT COMMANDS:
1. When you need to modify a file, output the FULL file content with clear markers
2. Use this format:
   [FILE: path/to/file.html]
   [CONTENT]
   (full file content here)
   [/CONTENT]

3. When you need to run Git commands, use:
   [GIT: git add .]
   [GIT: git commit -m "message"]
   [GIT: git push]

4. The system will automatically execute these commands for you
5. Always create backups before modifying files
6. You're in: C:\Users\chris\Desktop\family-nest-auctions

Continue helping with the demo data removal. Start by examining the seller dashboard.
"""
    
    conversation_history.append({
        "role": "system", 
        "content": system_message
    })
    print("Context loaded successfully!")
else:
    print("No context.txt file found. Starting fresh conversation.")

print("\n" + "="*60)
print("DeepSeek is ready with FILE SYSTEM and GIT access!")
print("="*60)
print("I can now:")
print("✅ Read files from your project")
print("✅ Write changes to files")
print("✅ Run Git commands (add, commit, push)")
print("✅ Deploy to Vercel")
print("="*60)
print(f"Full responses saved to: {full_output_file}")
print("="*60)

def execute_git_command(command):
    """Execute a git command and return the output"""
    try:
        # Remove [GIT: ] prefix if present
        if command.startswith('[GIT:'):
            command = command.replace('[GIT:', '').replace(']', '').strip()
        
        print(f"\n🔧 Executing: {command}")
        
        # Split command safely
        cmd_parts = shlex.split(command)
        
        # Run the command
        result = subprocess.run(
            cmd_parts,
            cwd=os.getcwd(),
            capture_output=True,
            text=True,
            shell=True  # Needed for Windows
        )
        
        if result.returncode == 0:
            print(f"✅ Success: {result.stdout}")
            return True, result.stdout
        else:
            print(f"❌ Error: {result.stderr}")
            return False, result.stderr
            
    except Exception as e:
        print(f"❌ Exception: {e}")
        return False, str(e)

def write_file(filepath, content):
    """Write content to a file"""
    try:
        # Clean up the content (remove markers if present)
        content = content.replace('[CONTENT]', '').replace('[/CONTENT]', '').strip()
        
        # Create backup if file exists
        if os.path.exists(filepath):
            backup = f"{filepath}.backup"
            import shutil
            shutil.copy2(filepath, backup)
            print(f"📦 Backup created: {backup}")
        
        # Write the new content
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        
        print(f"✅ File written: {filepath}")
        modified_files.append(filepath)
        return True
        
    except Exception as e:
        print(f"❌ Error writing file: {e}")
        return False

def process_response_for_actions(response):
    """Check if response contains file writes or git commands"""
    lines = response.split('\n')
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        
        # Check for git commands
        if line.startswith('[GIT:'):
            git_cmd = line
            success, output = execute_git_command(git_cmd)
            if success:
                # Insert the command output into the response display
                print(f"\n📌 Git output: {output}")
        
        # Check for file writes
        elif line.startswith('[FILE:'):
            # Extract filename
            filename = line.replace('[FILE:', '').replace(']', '').strip()
            
            # Find the content
            content_lines = []
            i += 1
            while i < len(lines) and '[/CONTENT]' not in lines[i]:
                if '[CONTENT]' in lines[i]:
                    content_lines.append(lines[i].replace('[CONTENT]', ''))
                else:
                    content_lines.append(lines[i])
                i += 1
            
            # Write the file
            content = '\n'.join(content_lines)
            write_file(filename, content)
        
        i += 1

def get_complete_response(messages):
    """Get a complete response, automatically handling truncation"""
    full_response = ""
    continuation_count = 0
    current_messages = messages.copy()
    
    while True:
        try:
            print(f"\n[Getting response part {continuation_count + 1}...]", end="", flush=True)
            
            # Get response with streaming
            response = api.chat_completion(
                messages=current_messages,
                stream=True
            )
            
            # Collect the streamed response
            current_part = ""
            for chunk in response:
                print(chunk, end="", flush=True)
                current_part += chunk
            
            full_response += current_part
            continuation_count += 1
            
            # Check if we need to continue
            if len(current_part) > 0 and current_part.rstrip()[-1] not in '.!?':
                print("\n\n[Response may be truncated. Getting continuation...]", flush=True)
                
                # Add a continuation prompt
                current_messages = messages.copy()
                current_messages.append({"role": "assistant", "content": full_response})
                current_messages.append({
                    "role": "user", 
                    "content": "Continue from where you left off. Don't repeat anything, just continue your previous response."
                })
                
                time.sleep(1)
            else:
                break
                
        except Exception as e:
            print(f"\nError during streaming: {e}")
            break
    
    print(f"\n\n[Complete! Got {continuation_count} part(s)]")
    
    # Process any file writes or git commands in the response
    process_response_for_actions(full_response)
    
    return full_response

while True:
    user_input = input("\nYou: ")
    if user_input.lower() == 'exit':
        break
    
    # Add user message to history
    conversation_history.append({"role": "user", "content": user_input})
    
    print("\nDeepSeek: ", end="", flush=True)
    
    # Get complete response with auto-continuation
    full_response = get_complete_response(conversation_history)
    
    # Add assistant's full response to history
    conversation_history.append({"role": "assistant", "content": full_response})
    
    # Save the complete response to a file
    with open(full_output_file, 'a', encoding='utf-8') as f:
        f.write(f"\n\n--- User: {user_input} ---\n")
        f.write(full_response)
        f.write("\n" + "="*50 + "\n")
    
    print("\n" + "-"*50)
    print(f"[Full response saved to {full_output_file}]")
    if modified_files:
        print(f"[Modified files: {', '.join(modified_files)}]")
    print("-"*50)