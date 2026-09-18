# Lucide via rails_icons. SVGs are a build artifact (gitignored vendor/icons).
#   bin/rails icons:sync          # no-op if already present
#   bin/rails icons:sync FORCE=1  # re-clone from GitHub
RailsIcons.configure do |config|
  config.default_library = "lucide"
  config.icons_path = "vendor/icons"

  # App CSS (not Tailwind). Stroke follows Lucide’s outline default.
  config.libraries.lucide.outline.default.css = "icon"
end
