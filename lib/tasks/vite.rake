# Ensure Vite assets are built during deployment.
# Hatchbox (and most Rails hosts) run `assets:precompile` automatically.
# This hook triggers `vite:build` so the manifest is generated in production.

if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance(["vite:build"])
end
