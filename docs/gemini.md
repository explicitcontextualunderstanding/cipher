# Using GEMINI_API_KEY with Cipher

This project supports using Google's Gemini (Generative AI) models. The code
looks for a GEMINI_API_KEY environment variable. There are two recommended
ways to provide the key on macOS while keeping it secure:

1. Store the key in macOS Keychain and read it from your shell:

   - Store the key once with:

     security add-generic-password -a $(whoami) -s GEMINI_API_KEY -w "<YOUR_KEY>"

   - Add this to your `~/.zshrc` so the key is available in interactive shells:

     export GEMINI_API_KEY="$(security find-generic-password -s GEMINI_API_KEY -w)"

   - Then restart your terminal or `source ~/.zshrc`.

2. Or set the env var directly (less secure):

   export GEMINI_API_KEY="<YOUR_KEY>"

The repo already includes a `.env.example` containing a `GEMINI_API_KEY` placeholder.

Running the Python example

1. Install the Python library used in the example:

   pip install google-generativeai

2. Run the example script:

   python3 scripts/generate_story.py

If the script fails to find the key it will print helpful guidance. If the
Generative API call fails, verify that the key is correct and that your account
has permission to use the model configured in the script.
