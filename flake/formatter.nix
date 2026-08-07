{
  self,
  forAllSystems,
  treefmtEval,
  ...
}: {
  formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);
  checks = forAllSystems (system: {
    formatting = treefmtEval.${system}.config.build.check self;
  });
}
