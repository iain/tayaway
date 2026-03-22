# typed: strict
# frozen_string_literal: true

# Set::SubclassCompatible is an internal Ruby module included in Set
# subclasses. Sorbet's bundled stdlib RBIs don't define it, but
# tapioca's generated RBI for chunky_png references it because
# ChunkyPNG::Palette inherits from Set.

module Set::SubclassCompatible; end
module Set::SubclassCompatible::ClassMethods; end
