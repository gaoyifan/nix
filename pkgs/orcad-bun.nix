{bun}:
bun.overrideAttrs (_: old: {
  version = "1.4.2";
  src = old.src.overrideAttrs {
    hash = "sha256-NjaPrvdSeHXV/6UuU81IAhdB8qg+tiCKjdZAaNQiqRM=";
  };
  meta = old.meta // {platforms = ["x86_64-linux"];};
})
