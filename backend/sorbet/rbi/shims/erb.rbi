# typed: strict
# frozen_string_literal: true

# ERB::Escape is a C extension module mixed into ERB::Util in Ruby 4.
# Sorbet's bundled stdlib RBIs don't define it, so tapioca's generated
# RBIs for erb, rdoc, and rspec-core reference an unresolved constant.

module ERB::Escape; end
