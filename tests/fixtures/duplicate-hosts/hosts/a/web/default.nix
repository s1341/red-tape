{ hostName, ... }:
{
  class = "nixos";
  value = {
    _type = "test-nixos-system";
    inherit hostName;
  };
}
