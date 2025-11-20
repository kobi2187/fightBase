# Installation Guide

## Install Nim

### Linux/macOS
```bash
curl https://nim-lang.org/choosenim/init.sh -sSf | sh
```

Then add to PATH (add to ~/.bashrc or ~/.zshrc):
```bash
export PATH=$HOME/.nimble/bin:$PATH
```

Reload shell:
```bash
source ~/.bashrc
```

### Alternative: Use package manager

**Ubuntu/Debian:**
```bash
sudo apt install nim
```

**macOS (Homebrew):**
```bash
brew install nim
```

**Arch Linux:**
```bash
sudo pacman -S nim
```

## Verify Installation

```bash
nim --version
# Should show: Nim Compiler Version X.X.X

nimble --version
# Should show: nimble vX.X.X
```

## Build the Project

```bash
cd /home/user/fightBase
nim c -r src/fight_notation.nim
# This compiles and runs the notation test

nim c src/fightBase.nim
# This compiles the main executable
```

## Run a Quick Test

```bash
# Run notation demo
nim c -r src/fight_notation.nim

# This will show:
# - FPN encoding (compact state representation)
# - Visual ASCII board
# - Compact one-line state
```

## Common Issues

### Issue: "nim: command not found"
**Solution**: Add Nim to PATH or reload your shell

### Issue: Compilation errors
**Solution**: Make sure you have the latest Nim version (1.6.0+)

### Issue: Missing modules
**Solution**: Install dependencies with nimble:
```bash
nimble install # (though we don't have external deps yet)
```

## Next Steps

After installation:
1. Run `nim c -r src/fight_notation.nim` to test notation
2. Create a simple visualization runner (see VISUALIZATION.md)
3. Run batch simulations
4. Explore the tablebase as it grows
