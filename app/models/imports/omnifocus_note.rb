# frozen_string_literal: true

module Imports
  # OmniFocus notes are XML: <p><run><lit>…</lit></run></p> plus style bags
  # (font-family, colors, link URLs). We emit Markdown: paragraphs and
  # [label](https://…) for linked runs.
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

        href = run.at_xpath("./style/value[@key='link']")&.text.to_s.strip
        if href.match?(ALLOWED_HREF)
          "[#{escape_label(lit)}](#{href})"
        else
          lit
        end
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
