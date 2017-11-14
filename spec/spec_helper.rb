$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
Thread.abort_on_exception = true

require 'simplecov'
require 'coveralls'

Coveralls::Output.silent = true

SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new([
  SimpleCov::Formatter::HTMLFormatter,
  Coveralls::SimpleCov::Formatter
])

SimpleCov.start do
  add_filter '/spec/'
  add_filter '/lib/phobos/test'
end

require 'phobos'
require 'pry-byebug'
require 'timecop'
require 'phobos/test'

Dir.entries('./spec/support').select { |f| f =~ /\.rb$/ }.each do |f|
  load "./spec/support/#{f}"
end

RSpec.configure do |config|
  include KafkaHelpers
  include PhobosHelpers
  include CLIHelpers

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.run_all_when_everything_filtered = true
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = false
  config.expose_dsl_globally = true

  if config.files_to_run.one?
    config.default_formatter = 'doc'
  end

  config.before(:each) do
    Phobos.silence_log = true
    Phobos.configure('config/phobos.yml.example')
  end

  config.profile_examples = false

  config.order = :random

  Kernel.srand config.seed
end
