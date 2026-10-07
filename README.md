# New Repo

A small macOS menu bar app that creates a new GitHub repository on your account and clones it, in one step.

Click the **+** in the menu bar, type a name, and press Return.

- Checks the repository name against GitHub's rules as you type. A green tick means the name is valid, isn't already used on your account, and has no matching folder in the clone location. Invalid names get a cleaned-up suggestion, for example `My Cool Repo` becomes `My-Cool-Repo`.
- Has a folder picker for where to clone. The last folder you used is remembered.
- Creates repositories as **private** unless you tick **Make public**.
- Every new repository starts with a README committed to `main`, so `main` is always the default branch.
- When it's done, you can open the new clone in Finder, Terminal, or on GitHub.

The app doesn't store any GitHub credentials. It runs the [GitHub CLI](https://cli.github.com) (`gh`), which you've already signed in to:

```sh
gh repo create <name> --private --add-readme
# If your GitHub account names first branches something other than main:
gh api -X POST repos/<you>/<name>/branches/<branch>/rename -f new_name=main
gh repo clone <you>/<name>                 # run from the folder you chose
```

## Requirements

- macOS 13 (Ventura) or later
- Swift 5.9 or later: Xcode, or the Command Line Tools (`xcode-select --install`)
- The GitHub CLI, installed and signed in:

  ```sh
  brew install gh
  gh auth login
  ```

## Build and install

```sh
./scripts/build-app.sh --install
```

This builds `build/NewRepo.app`, copies it to `/Applications`, and launches it. Leave out `--install` to only build it. To start the app automatically, tick **Open at login** in the popover.

For development, `swift run` launches it directly (without the app bundle, so **Open at login** won't work), and `swift test` runs the name-validation tests.

## Troubleshooting

- **"Couldn't find the GitHub CLI"**: the app looks for `gh` in `/opt/homebrew/bin`, `/usr/local/bin`, `/opt/local/bin`, `~/.local/bin`, and finally your login shell's `PATH`.
- **The repo is created but cloning fails**: if `gh config get git_protocol` is `https`, run `gh auth setup-git` so `git` can use your `gh` credentials. If it's `ssh`, check that your SSH key is loaded (`ssh -T git@github.com`).
