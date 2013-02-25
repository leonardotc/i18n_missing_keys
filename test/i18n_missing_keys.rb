#!/usr/bin/env ruby

# require './lib/tasks/i18n_missing_keys.rake'

require 'rubygems' rescue ''
require 'test/unit'
require 'rake'
require 'mocha'
require 'active_support'
require 'shoulda'
require 'fileutils'

# Fake Rails class that enables us to load the i18n_missing_keys.yml
# file.
class Rails
  def Rails.root
    return FileUtils.pwd
  end
end

# Do not re-load the environment task
class Rake::Task
  def invoke_prerequisites(task_args, invocation_chain)
    @prerequisites.reject{|n| n == "environment"}.each do |n|
      prereq = application[n, @scope]
      prereq_args = task_args.new_scope(prereq.arg_names)
      prereq.invoke_with_call_chain(prereq_args, invocation_chain)
    end
  end
end

class RakeTaskTest < Test::Unit::TestCase
  def setup
    @rake = Rake::Application.new
    Rake.application = @rake
    load 'lib/tasks/i18n_missing_keys.rake'
  end

  def teardown
    Rake.application = nil
  end

  def invoke_task
    @rake['i18n:missing_keys'].invoke
  end

  def test_should_use_the_class
    MissingKeysFinder.expects(:new).returns(mock(:find_missing_keys => []))
    invoke_task
  end
end

class MissingKeysFinderTest < Test::Unit::TestCase
  def setup
    load 'lib/tasks/i18n_missing_keys.rake'

    @backend = I18n.backend
    @backend.stubs({
      :init_translations => true,
      :available_locales => ['en', 'da'],
      :translations => {:en => {:hi => 'Hi'}, :da => {:hi => 'Hej'}}
    })
    @finder = ::MissingKeysFinder.new(@backend)
    
    # Silence the finder
    @finder.stubs(:output_available_locales).returns('')
    @finder.stubs(:output_unique_key_stats).returns('')
    @finder.stubs(:output_missing_keys).returns('')
  end

  context 'find_missing_keys' do
    context 'when no keys are missing' do
      should 'return an empty hash' do
        result = @finder.find_missing_keys
        assert_instance_of Hash, result
        assert result.empty?, result.inspect
      end
    end

    context 'when a key is missing from a locale' do
      should 'return that key in the hash' do
        @finder.expects(:key_exists?).with('hi', 'en').returns(true)
        @finder.expects(:key_exists?).with('hi', 'da').returns(false)
        result = @finder.find_missing_keys
        assert result.include?('hi'), result.inspect
      end
    end
  end
  
  context 'all_keys' do
    should 'return an array' do
      result = @finder.all_keys
      assert_instance_of Array, result
    end

    should 'contain all the keys' do
      @backend.stubs(:translations).returns({:en => {:greetings => {:hi => 'Hi', :hello => 'Hello'}}, :da => {:greetings => {:hi => 'Hej'}}})
      result = @finder.all_keys
      assert_equal ['greetings.hello', 'greetings.hi'], result.sort
    end
    
    should 'work for Hans' do
      translations = YAML.load(<<-EOF
        en:
          messages:
            inclusion: "is not included in the list"
            models:
              user:
                email:  "should look like an email addres"
          label_messages:
            validates_acceptance_of:  'Must be accepted'  
        EOF
      )
      @backend.stubs(:translations).returns(translations)
      result = @finder.all_keys
      assert_equal ['label_messages.validates_acceptance_of', 'messages.inclusion', 'messages.models.user.email'], result
    end 
  end

  context "ignore translations listed in ignore_missing_keys.yml" do
    setup do
      @backend.stubs(:translations).returns(
                                            {
                                              :it => {:activerecord => {:foo => 'foo'}, :missing => { :one => 'uno'}},
                                              :en => {:activerecord => {}, :missing => {}}
                                            })
    end

    should "ignore english activerecord" do
      result = @finder.find_missing_keys
      assert result["missing.one"] = ["en", "da"]
      assert result["activerecord.foo"] = ["da"]
    end

  end

  context 'key_exists?' do
    setup do
      @backend.stubs(:translations).returns({
        :en => {:greetings => {:hi => 'Hi', :hello => 'Hello'}},
        :da => {:greetings => {:hi => 'Hej'}}
      })
    end

    should 'return true when key exists in locale' do
      assert @finder.key_exists?('greetings', 'en')
      assert @finder.key_exists?('greetings.hi', 'en')
    end

    should 'return false when key does not exist in locale' do
      assert_equal false, @finder.key_exists?('omg', 'en')
    end

    should 'return false when key only exists in another locale' do
      assert_equal false, @finder.key_exists?('hello', 'da')
    end
  end
end
