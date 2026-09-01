# frozen_string_literal: true

namespace :admin do
  namespace :css do
    desc "Build the Flowbite admin Tailwind bundle"
    task :build do
      minify = ENV["RAILS_ENV"] == "production"
      command = [
        "bundle", "exec", "tailwindcss",
        "-i", "./app/assets/tailwind/admin.css",
        "-o", "./app/assets/builds/admin.css"
      ]
      command << "--minify" if minify
      sh(*command)
    end
  end
end

if Rake::Task.task_defined?("tailwindcss:build")
  Rake::Task["tailwindcss:build"].enhance([ "admin:css:build" ])
end

if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance([ "admin:css:build" ])
end
