# frozen_string_literal: true

namespace :icons do
  desc "Sync Lucide into vendor/icons (skipped if present; FORCE=1 to re-download)"
  task sync: :environment do
    require "icons/sync"
    require "stringio"

    dest = Rails.root.join(RailsIcons.configuration.icons_path, "lucide")
    present = dest.glob("**/*.svg").any?

    if present && ENV["FORCE"].blank?
      puts "[icons] Lucide already at #{dest.relative_path_from(Rails.root)} (FORCE=1 to re-sync)"
      next
    end

    FileUtils.rm_rf(dest) if present

    # Icons::Sync prompts on failure; don't hang CI / Docker.
    previous_stdin = $stdin
    $stdin = StringIO.new("n\n") unless previous_stdin.tty?
    begin
      Icons::Sync.new("lucide").now
    ensure
      $stdin = previous_stdin
    end
  end
end
