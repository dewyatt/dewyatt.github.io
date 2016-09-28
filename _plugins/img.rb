# {% img 16.jpg|16t.jpg 15.jpg|15t.jpg %}
# {% img groupname 15.jpg 16.jpg %}
module Jekyll
  class ImgTag < Liquid::Tag

    def initialize(tag_name, input, tokens)
      super

      @items = input.split(/\s+/)
      @group = ''

      if @items[0].count('.') == 0
        @group = @items[0]
        @items.shift
      end

    end

    def render(context)
      out = ''
      @items.each {|item|
        @image, @thumb = item.split('|')
        @image = Liquid::Template.parse(@image).render context
        if @thumb == nil
          @thumb = @image
        else
          @thumb = Liquid::Template.parse(@thumb).render context
        end

        out += %{<img class="jslghtbx-thmb"
               src="/assets/images/#{@thumb}"
               data-jslghtbx="/assets/images/#{@image}"
               data-jslghtbx-group="#{@group}" />
        }
      }
      return out
    end
  end
end

Liquid::Template.register_tag('img', Jekyll::ImgTag)
