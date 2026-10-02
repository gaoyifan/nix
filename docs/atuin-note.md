# Atuin Notes

- Zsh Up/Down: on an empty command line, the first Up recalls the last command executed in this shell. Further Up presses browse Atuin history (current directory, then global), skipping that command. With typed input, Up uses prefix search. Down restores the original input.
- `atuin history init-store`: import entries from local `history.db` into `records.db` using the current key.
- `atuin store purge`: delete records in `records.db` that cannot be decrypted with the current key.
