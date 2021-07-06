file 'lib/worf/constants.rb' => ['lib/worf/constants.yml', 'lib/worf/constants.erb'] do |t|
  require 'psych'
  require 'erb'
  constants = Psych.load_file t.prereqs.first
  erb = ERB.new File.read(t.prereqs[1]), trim_mode: '-'
  File.write t.name, erb.result(binding)
end

require "rake/testtask"

Rake::TestTask.new do |t|
  t.libs << "test"
  t.test_files = FileList['test/*_test.rb']
  t.verbose = true
  t.warning = true
end

task :default => 'lib/worf/constants.rb'
