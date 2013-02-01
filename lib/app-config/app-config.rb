require 'active_record'

module AppConfig
  extend AppConfig::Processor

  FORMATS = ['string', 'array', 'hash', 'boolean'].freeze
  RESTRICTED_KEYS = [
    'id',
    'to_s',
    'configure',
    'load',
    'flush',
    'reload',
    'keys',
    'empty?',
    'method_missing',
    'exist?',
    'source_model',
    'configuration',
    'save'
  ].freeze

  @@options = {}
  @@records = {}

  # Configure app config
  def self.configure(opts={})
    @@options[:model]   = opts[:model]  || Setting
    @@options[:key]     = opts[:key]    || 'keyname'
    @@options[:value]   = opts[:value]  || 'value'
    @@options[:format]  = opts[:format] || 'value_format'
  end

  # Returns a configuration options
  def self.configuration
    @@options
  end

  # Load and process application settings
  def self.load
    @@records = fetch
  end

  # Delete all settings
  def self.flush
    @@records.clear
  end

  # Safe method to reload new settings
  def self.reload
    records = fetch rescue nil
    @@records = records || {}
  end

  # Manually set (or add) a key
  def self.set_key(keyname, value, format='string')
    raise InvalidKeyName, "Invalid key name: #{keyname}" if RESTRICTED_KEYS.include?(keyname)
    @@records[keyname] = process(value, format)
  end

  # Returns all configuration keys
  def self.keys
    @@records.keys
  end

  # Returns true if there are no settings available
  def self.empty?
    @@records.empty?
  end

  # Get configuration option
  def self.[](key)
    @@records[key.to_s]
  end

  # Get configuration option by attribute
  def self.method_missing(method, *args)
    @@records[method.to_s]
  end

  # Returns true if configuration key exists
  def self.exist?(key)
    @@records.key?(key)
  end

  # Returns class that defined as source
  def self.source_model
    @@options[:model]
  end

  def self.to_hash
    hash = {}

    begin
      keys.map do |k|
        hash[k.to_sym] = { @@options[:value].to_sym => self[k.to_sym] }
      end
      hash
    end
  end

  protected

  # Checks the column structure of the source model
  def self.check_structure
    klass = @@options[:model]
    keys = [@@options[:key], @@options[:value], @@options[:format]]
    return (keys - klass.column_names).empty?
  end

  # Fetch data from model
  def self.fetch
    raise InvalidSource, 'Model is not defined!'     if @@options[:model].nil?
    raise InvalidSource, 'Model was not found!'      unless @@options[:model].superclass == ActiveRecord::Base
    raise InvalidSource, 'Model fields are invalid!' unless check_structure

    records = {}

    begin
      @@options[:model].send(:all).map do |c|
        records[c.send(@@options[:key].to_sym)] = process(
          c.send(@@options[:value].to_sym),
          c.send(@@options[:format].to_sym)
        )
      end
      records
    rescue ActiveRecord::StatementInvalid => ex
      raise InvalidSource, ex.message
    end
  end

  # Save data to model
  def self.save
    raise InvalidSource, 'Model is not defined!'     if @@options[:model].nil?
    raise InvalidSource, 'Model was not found!'      unless @@options[:model].superclass == ActiveRecord::Base
    raise InvalidSource, 'Model fields are invalid!' unless check_structure

    hash = self.to_hash

    begin
      keys.map do |k|
        record = @@options[:model].find(:first, :conditions => {@@options[:key].to_sym => k.to_s})
        unless record.nil?
          record.send("#{@@options[:key].to_sym}=",k)
          record.send("#{@@options[:value].to_sym}=",@@records[k].to_s)
          record.send("#{@@options[:format].to_sym}=",(/TrueClass|FalseClass/.match(@@records[k].class.to_s) ? 'boolean' : @@records[k].class.to_s.downcase))
          record.save
        else
          new = @@options[:model].new
          new.send("#{@@options[:key].to_sym}=",k)
          new.send("#{@@options[:value].to_sym}=",@@records[k].to_s)
          new.send("#{@@options[:format].to_sym}=",(/TrueClass|FalseClass/.match(@@records[k].class.to_s) ? 'boolean' : @@records[k].class.to_s.downcase))
          new.save
        end
      end
    rescue ActiveRecord::StatementInvalid => ex
      raise InvalidSource, ex.message
    end
  end
end
