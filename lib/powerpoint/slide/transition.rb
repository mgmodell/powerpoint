module Powerpoint
  module Slide
    module Transition
      TYPES = %w[
        blinds checker circle comb cover cut diamond dissolve fade newsflash
        plus pull push random randomBar split strips wedge wheel wipe zoom
      ].freeze

      def transition_xml
        return '' unless @transition
        raise ArgumentError, 'transition must be a Hash' unless @transition.is_a?(Hash)

        type = (@transition[:type] || @transition['type'] || 'fade').to_s
        raise ArgumentError, "unsupported transition type: #{type}" unless TYPES.include?(type)

        duration = @transition[:duration] || @transition['duration']
        if duration && (!duration.is_a?(Integer) || duration <= 0)
          raise ArgumentError, 'transition duration must be a positive integer in milliseconds'
        end

        duration_attribute = duration ? %( p14:dur="#{duration}") : ''
        %(<p:transition#{duration_attribute} xmlns:p14="http://schemas.microsoft.com/office/powerpoint/2010/main"><p:#{type}/></p:transition>)
      end
    end
  end
end
