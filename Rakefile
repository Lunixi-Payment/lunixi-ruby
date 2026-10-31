# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |task|
  task.libs << 'lib'
  task.pattern = 'test/**/*_test.rb'
  task.warning = true
end

task default: :test

namespace :rails do
  desc 'Run the Rails sample integration suite using its isolated test database'
  task :test do
    Dir.chdir('samples/rails') do
      ruby '-Itest', '-e', 'Dir["test/**/*_test.rb"].sort.each { |path| require_relative path }'
    end
  end
end
