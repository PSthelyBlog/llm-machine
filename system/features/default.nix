# Every directory here is a feature, and every feature is on.
# To remove a feature, delete its directory.
{ lib, ... }:
let
  features = lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./.));
in
{
  imports = map (name: ./${name}) features;
}
