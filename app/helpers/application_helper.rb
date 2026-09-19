module ApplicationHelper
  # Class string for `<button>`, `button_to`, and `form.submit`.
  def btn(*variants)
    ButtonComponent.classes(*variants)
  end

  NOTE_TAGS = %w[ p br a strong em ul ol li code pre blockquote table thead tbody tr th td del h1 h2 h3 hr input ].freeze
  NOTE_ATTRS = %w[ href type disabled checked colspan rowspan ].freeze

  def formatted_notes(text)
    return if text.blank?

    html = Commonmarker.to_html(
      text,
      options: {
        extension: {
          strikethrough: true,
          tagfilter: true,
          table: true,
          autolink: true,
          tasklist: true,
          shortcodes: false
        },
        render: { unsafe: false }
      },
      plugins: { syntax_highlighter: nil }
    )
    sanitize(html, tags: NOTE_TAGS, attributes: NOTE_ATTRS)
  end
end
