require 'active_record'

# +inherits_from+ is an +ActiveRecord+ plugin designed to allow simple multiple table (class) inheritance.
# 
# Example:
#   class Product < ActiveRecord::Base
#     inherits_from :product
#   end
#
#   class Book < ActiveRecord::Base
#     inherits_from :product
#   end
#
#   class Video < ActiveRecord::Base
#     inherits_from :product
#   end
#
#   book = Book.find(1)
#   book.name => "Agile Development with Rails"
#   book.author => "Dave Thomas"
#
#   video = Video.find(2)
#   book.name => "Twilight Zone Season 1"
#   book.actors => "Rod Serling"

module ActiveRecord::Validations::ClassMethods
  # Validate associations through the inheritance chain and pass the error 
  # messages back through
  def validates_associated(*associations)
    associations.each do |association|
      class_eval do
        validates_each(associations) do |record, associate_name, value|
          associates = record.send(associate_name)
          associates = [associates] unless associates.respond_to?('each')
          associates.each do |associate|
            if associate && !associate.valid?
              associate.errors.each do |key, value|
                record.errors.add(key, value)
              end
            end
          end
        end
      end
    end
  end
end

class ActiveRecord::Associations::AssociationProxy

  alias_method :rails_raise_on_type_mismatch, :raise_on_type_mismatch

  # Make type-checking "inheritance-friendly"
  def raise_on_type_mismatch(record)
    # check if record does inheritance
    if record.respond_to? :superclass 
      unless record.superclass == @reflection.class_name.constantize
        rails_raise_on_type_mismatch(record)
      end
    else
      rails_raise_on_type_mismatch(record)
    end
  end
end

class ActiveRecord::Base
  attr_reader :reflection
  
  # Creates an inheritance association and generates proxy methods in the inherited object for easy access to the parent.
  # Currently, the options are ignored.
  #
  # Example:
  #   class Book < ActiveRecord::Base
  #     inherits_from :product
  #   end
  def self.inherits_from(association_id, options = {})
    belongs_to association_id
    validates_associated association_id
    
    reflection = create_reflection(:belongs_to, association_id, options, self)
    
    association_class = Object.const_get(reflection.class_name)
    
    inherited_column_names = association_class.column_names.reject { |c| self.column_names.grep(c).length > 0 || c == "type"}

    inherited_reflections = association_class.reflections.map { |key,value| key.to_s }
    
    (inherited_column_names + inherited_reflections).each do |name|
      define_method(name) do
        init_inherited_assoc(association_id)
        klass = send(association_id)
      
        klass.send(name)
      end
    
      define_method("#{name}=") do |new_value|
        init_inherited_assoc(association_id)
        klass = send(association_id)
      
        klass.send("#{name}=", new_value)
      end
    end
    
    inherited_reflections.each do |name|
      %w{ build create }.each do |method|
        define_method("#{method}_#{name}") do |*params|
          init_inherited_assoc(association_id)
          klass = send(association_id)
      
          klass.send("#{method}_#{name}", *params)
        end
      end
      
    end

    define_method(:superclass) do
      association_id.to_s.camelize.constantize
    end

    define_method(:column_for_attribute) do |att|
      super(att) || association_class.columns_hash[att.to_s]
    end
    
    before_callback = <<-end_eval
      init_inherited_assoc("#{association_id}")
      instance_variable_get("@#{association_id}").save
    end_eval
    
    before_create(before_callback)
    before_update(before_callback)
  end
  
  def self.is_a_superclass
    define_method('subobject') do 
      subtype.constantize.send("find_by_#{self.class.name.underscore}_id", send("id"))
    end
  end
  
  private
  # Ensures that there is an association to access, if not, creates one.
  def init_inherited_assoc(association_id)
    if new_record? and instance_variable_get("@#{association_id}").nil?
      send("build_#{association_id}")
      instance_variable_get("@#{association_id}").subtype = self.class.to_s
    end
  end
end
