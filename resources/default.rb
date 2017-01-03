actions :create, :delete
default_action :create

attribute :name, :kind_of => String, :name_attribute => true
attribute :expires, :kind_of => Integer
attribute :expires_factor, :kind_of => Integer
attribute :key_size, :kind_of => Integer
attribute :ca, :kind_of => String
attribute :path, :kind_of => String
attribute :path_mode, :kind_of => [String, Integer]
attribute :path_recursive, :kind_of => [TrueClass, FalseClass]
attribute :ca_path, :kind_of => String
attribute :ca_owner, :kind_of => [NilClass, String]
attribute :ca_group, :kind_of => [NilClass, String]
attribute :ca_path_mode, :kind_of => [String, Integer]
attribute :ca_path_recursive, :kind_of => [TrueClass, FalseClass]
attribute :owner, :kind_of => String
attribute :group, :kind_of => String
attribute :public_mode, :kind_of => [String, Integer]
attribute :private_mode, :kind_of => [String, Integer]
attribute :data_bag, :kind_of => String
attribute :bundle_ca, :kind_of => [TrueClass, FalseClass]
attribute :standalone, :kind_of => [TrueClass, FalseClass]
attribute :subject_alternate_names, :kind_of => [NilClass, FalseClass, Array]
