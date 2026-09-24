# frozen_string_literal: true

module Imports
  # OmniFocus notes are XML: <p><run><lit>…</lit></run></p> plus style bags.
  # Markdown: paragraphs, [label](url), **bold**, *italic*, ~~strike~~.
  # Colors, fonts, underline, alignment, and lists are dropped.
  class OmnifocusNote
    ALLOWED_HREF = /\Ahttps?:\/\/[^\s]+\z/i

    def self.to_markdown(node)
      new(node).to_markdown
    end

    def initialize(node)
      @node = node
    end

    def to_markdown
      return if @node.nil?

      paragraphs = paragraph_nodes.map { |p| paragraph_markdown(p) }.compact_blank
      if paragraphs.any?
        paragraphs.join("\n\n")
      else
        fallback
      end.presence
    end

    private
      def paragraph_nodes
        root = @node.at_xpath("./text") || @node
        ps = root.xpath("./p")
        ps.any? ? ps : []
      end

      def paragraph_markdown(paragraph)
        runs = paragraph.xpath("./run")
        if runs.any?
          runs.map { |run| run_markdown(run) }.join
        else
          paragraph.xpath(".//lit").map(&:text).join
        end
      end

      def run_markdown(run)
        lit = run.at_xpath("./lit")&.text.to_s
        return "" if lit.blank?

        styled = emphasize(lit, run)
        href = style_value(run, "link")
        if href.match?(ALLOWED_HREF)
          "[#{escape_label(styled)}](#{href})"
        else
          styled
        end
      end

      def emphasize(text, run)
        inner = text
        inner = "~~#{inner}~~" if struck?(run)
        inner = "*#{inner}*" if italic?(run)
        inner = "**#{inner}**" if bold?(run)
        inner
      end

      def bold?(run)
        weight = style_value(run, "font-weight")
        return true if weight.match?(/\A[6-9]\z/)
        truthy?(style_value(run, "font-bold"))
      end

      def italic?(run)
        truthy?(style_value(run, "font-italic"))
      end

      def struck?(run)
        style = style_value(run, "strikethrough-style")
        return true if style.present? && style != "none" && style != "0"
        truthy?(style_value(run, "strikethrough"))
      end

      def style_value(run, key)
        run.at_xpath("./style/value[@key='#{key}']")&.text.to_s.strip
      end

      def truthy?(value)
        %w[true 1 yes].include?(value.downcase)
      end

      def escape_label(text)
        text.gsub("[", "\\[").gsub("]", "\\]")
      end

      def fallback
        clone = @node.dup
        clone.xpath(".//style|.//value|.//color").each(&:remove)
        clone.text.to_s.gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip.presence
      end
  end
end
