################################################################################
#
#      Author: Stephen Nelson-Smith <stephen@atalanta-systems.com>
#      Author: Zachary Patten <zachary@jovelabs.com>
#   Copyright: Copyright (c) 2011-2012 Atalanta Systems Ltd
#     License: Apache License, Version 2.0
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
################################################################################

module Cucumber
  module Chef

    class ConfigError < Error; end

    class Config
      extend(Mixlib::Config)

      KEYS = %w( mode provider ).map(&:to_sym) unless const_defined?(:KEYS)
      MODES = %w( user test ).map(&:to_sym) unless const_defined?(:MODES)
      PROVIDERS = %w( aws vagrant ).map(&:to_sym) unless const_defined?(:PROVIDERS)

      PROVIDER_AWS_KEYS = %w( aws_access_key_id aws_secret_access_key region availability_zone aws_ssh_key_id identity_file ).map(&:to_sym) unless const_defined?(:PROVIDER_AWS_KEYS)

################################################################################

      def self.inspect
        configuration.inspect
      end

################################################################################

      def self.duplicate(input)
        output = Hash.new
        input.each do |key, value|
          output[key] = (value.is_a?(Hash) ? self.duplicate(input[key]) : value.to_s.dup)
        end
        output
      end

      def self.load
        config_rb = Cucumber::Chef.locate(:file, ".cucumber-chef", "config.rb")
        $logger.info { "Attempting to load cucumber-chef configuration from '%s'." % config_rb }
        self.from_file(config_rb)
        self.verify
        $logger.info { "Successfully loaded cucumber-chef configuration from '%s'." % config_rb }

        log_dump = self.duplicate(self.configuration)
        log_dump[:aws].merge!(:aws_access_key_id => "[REDACTED]", :aws_secret_access_key => "[REDACTED]")
        $logger.debug { log_dump.inspect }

        self
      rescue Errno::ENOENT, UtilityError
        raise ConfigError, "Could not find your cucumber-chef configuration file; did you run 'cucumber-chef init'?"
      end

      def self.test
        self.load
        self[:mode] = :test
        self
      end

################################################################################

      def self.verify
        self.verify_keys
        self.verify_provider_keys
        eval("self.verify_provider_#{self[:provider].to_s.downcase}")
        $logger.debug { "Configuration verified successfully" }
      end

################################################################################

      def self.verify_keys
        $logger.debug { "Checking for missing configuration keys" }
        missing_keys = KEYS.select{ |key| !self[key.to_sym] }
        if missing_keys.count > 0
          message = "Configuration incomplete, missing configuration keys: #{missing_keys.join(", ")}"
          $logger.fatal { message }
          raise ConfigError, message
        end

        $logger.debug { "Checking for invalid configuration keys" }
        invalid_keys = KEYS.select{ |key| !eval("#{key.to_s.upcase}S").include?(self[key]) }
        if invalid_keys.count > 0
          message = "Configuration incomplete, invalid configuration keys: #{invalid_keys.join(", ")}"
          $logger.fatal { message }
          raise ConfigError, message
        end
      end

################################################################################

      def self.verify_provider_keys
        $logger.debug { "Checking for missing provider keys" }
        missing_keys = eval("PROVIDER_#{self[:provider].to_s.upcase}_KEYS").select{ |key| !self[self[:provider]].key?(key) }
        if missing_keys.count > 0
          message = "Configuration incomplete, missing provider configuration keys: #{missing_keys.join(", ")}"
          $logger.fatal { message }
          raise ConfigError, message
        end
      end

################################################################################

      def self.verify_provider_aws
        if self[:aws][:aws_access_key_id] && self[:aws][:aws_secret_access_key]
          compute = Fog::Compute.new(:provider => 'AWS',
                                     :aws_access_key_id => self[:aws][:aws_access_key_id],
                                     :aws_secret_access_key => self[:aws][:aws_secret_access_key])
          compute.describe_availability_zones
        end
      rescue Fog::Service::Error => err
        message = "Invalid AWS credentials.  Please check your configuration."
        $logger.fatal { message }
        raise ConfigError, message
      end

      def self.verify_provider_vagrant
        message = "Not yet implemented."
        $logger.fatal { message }
        raise ConfigError, message
      end

################################################################################

      def self.aws_image_id
        if self[:aws][:aws_image_id]
          return self[:aws][:aws_image_id]
        elsif (self[:aws][:ubuntu_release] && self[:aws][:region])
          ami = Ubuntu.release(self[:aws][:ubuntu_release]).amis.find do |ami|
            ami.arch == (self[:aws][:aws_instance_arch] || "i386") &&
            ami.root_store == (self[:aws][:aws_instance_disk_store] || "instance-store") &&
            ami.region == self[:aws][:region]
          end
          return ami.name if ami
        end
        message = "Could not find a valid AMI image ID.  Please check your configuration."
        $logger.fatal { message }
        raise ConfigError, message
      end

################################################################################

      mode            :user
      prerelease      true

      provider        :aws
      librarian_chef  false

      user            ( ENV['OPSCODE_USER'] || ENV['USER'] )

      aws             Hash[ :ubuntu_release => "precise",
                            :aws_instance_arch => "i386",
                            :aws_instance_disk_store => "ebs",
                            :aws_instance_type => "m1.small",
                            :aws_security_group => "cucumber-chef" ]

      vagrant         Hash.new

################################################################################

    end

  end
end

################################################################################
