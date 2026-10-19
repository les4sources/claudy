module MailIntake
  # Le corps d'un mail tel qu'on le lit dans la Boite de réception.
  #
  # Avant, on ne gardait que `strip_tags` du HTML : les sauts de ligne
  # disparaissaient avec les <div>, les entités (&nbsp;, &lt;) restaient
  # visibles et la réponse citée se mêlait au texte. Ici, le HTML est assaini
  # (balises de texte seulement, aucun style, aucune image distante) et coupé
  # en deux : ce que l'expéditeur a écrit, puis le message cité, replié à
  # l'écran.
  #
  # La lecture part du brut (.eml) gardé sur le mail : elle profite donc aussi
  # aux mails relevés avant elle. `VERSION` invalide le cache quand la
  # lecture change.
  class Body
    VERSION = 1

    Reading = Data.define(:format, :main, :quoted) do
      def html? = format == "html"
      def quoted? = quoted.present?
    end

    TAGS = %w[p br div span a b strong i em u s strike ul ol li blockquote pre code hr
              h1 h2 h3 h4 h5 h6 table thead tbody tfoot tr td th small sub sup].freeze
    ATTRIBUTES = %w[href colspan rowspan].freeze
    LINE = "\u0001".freeze
    BLOCKS = %w[p div li tr h1 h2 h3 h4 h5 h6 blockquote table ul ol pre hr].freeze
    DROPPED = "script, style, head, title, meta, link, img, svg, video, audio, iframe, object, form, input, button"

    # Marqueurs posés par les messageries autour de la réponse citée.
    QUOTE_SELECTORS = [
      ".gmail_quote_container", ".gmail_quote", ".yahoo_quoted", "[id*=yahoo_quoted]",
      "#divRplyFwdMsg", "#appendonsend", "#mail-editor-reference-message-container",
      ".moz-cite-prefix", ".OutlookMessageHeader", "blockquote"
    ].join(", ")
    WROTE = /(a écrit|wrote|schrieb|schreef|escribió|ha scritto)\s*:?\s*\z/i
    ATTRIBUTION = /\A\s*(Le|On|Am|Op|El|Il)\s.{5,300}#{WROTE.source}/im
    SEPARATOR = /\A\s*-{2,}\s*(Original Message|Message d'origine|Forwarded message|Message transféré)/i
    HEADER_FROM = /\A\s*(De|From|Van|Von)\s*:\s*\S/
    HEADER_NEXT = /^\s*(Envoyé|Sent|Date|Verzonden|Gesendet)\s*:/

    def self.for(message)
      blob = message.raw.attached? ? message.raw.blob : nil
      cached = Rails.cache.fetch(["mail-body", VERSION, message.id, blob&.checksum]) do
        reading = blob ? from_raw(message.raw.download) : nil
        (reading || from_text(legacy_text(message.body_text))).to_h
      end
      Reading.new(**cached)
    rescue StandardError
      from_text(legacy_text(message.body_text))
    end

    def self.from_raw(raw)
      from_mail(::Mail.new(raw))
    rescue StandardError
      nil
    end

    def self.from_mail(mail)
      html = html_source(mail)
      (from_html(html) if html.present?) || from_text(plain_source(mail))
    end

    # Le texte gardé en base (`body_text`), lu par Jev et par le serveur MCP :
    # celui que l'expéditeur a écrit s'il y en a un, sinon son HTML converti.
    def self.text_of(mail)
      text = plain_source(mail)
      text = html_to_text(html_source(mail)) if text.blank?
      tidy(text)
    end

    def self.from_html(html)
      body = parse(html)
      main, quoted = split(body)
      main_html = sanitize(main)
      return if text_of_html(main_html).empty? && quoted.blank?

      Reading.new(format: "html", main: main_html, quoted: quoted.present? ? sanitize(quoted) : nil)
    end

    def self.from_text(text)
      text = tidy(text)
      lines = text.lines
      index = text_quote_start(lines)
      return Reading.new(format: "text", main: text.presence || "", quoted: nil) unless index

      Reading.new(format: "text", main: lines[0...index].join.strip, quoted: lines[index..].join.strip)
    end

    # Comme un navigateur : les blancs du source ne comptent pas, chaque bloc
    # ouvre une ligne (une seule entre deux blocs voisins), <br> en ouvre une.
    def self.html_to_text(html)
      return "" if html.blank?

      body = parse(html)
      body.xpath(".//text()[not(ancestor::pre)]").each { |node| node.content = node.content.gsub(/\s+/, " ") }
      body.css("br").each { |br| br.replace("\n") }
      body.css("li").each { |li| li.prepend_child("• ") }
      body.css(BLOCKS.join(", ")).each do |node|
        node.add_previous_sibling(LINE)
        node.add_next_sibling(LINE)
      end
      tidy(body.text.gsub(/ *#{LINE}[#{LINE} ]*/o, "\n").gsub(/^ +/, ""))
    end

    # --- private --------------------------------------------------------------

    def self.html_source(mail)
      part = mail.html_part || (mail.mime_type == "text/html" ? mail : nil)
      utf8(part&.decoded)
    end

    def self.plain_source(mail)
      part = mail.text_part || (!mail.multipart? && mail.mime_type != "text/html" ? mail : nil)
      utf8(part&.decoded)
    end

    def self.utf8(text)
      text.to_s.dup.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
    end

    # Les mails relevés avant cette lecture ont un `body_text` passé par
    # `strip_tags`, entités comprises.
    def self.legacy_text(text)
      CGI.unescapeHTML(text.to_s).gsub(/&nbsp;?/i, " ")
    end

    def self.tidy(text)
      text.to_s.gsub("\r\n", "\n").tr(" ", " ")
          .gsub(/[ \t]+$/, "").gsub(/\n{3,}/, "\n\n").strip.truncate(20_000)
    end

    def self.parse(html)
      doc = Nokogiri::HTML5(html.to_s, max_errors: 0)
      body = doc.at("body") || doc.root
      body.css(DROPPED).each(&:remove)
      body.xpath(".//comment()").each(&:remove)
      body.css("[style]").each { |node| node.remove if node["style"] =~ /display\s*:\s*none/i }
      body
    end

    # Coupe le corps au premier marqueur de citation : ce qui le précède est le
    # message, le marqueur et tout ce qui le suit est la citation. Si rien ne
    # précède (un transfert sans un mot), on n'en replie rien.
    def self.split(body)
      marker = quote_marker(body)
      return [body.inner_html, nil] unless marker

      quoted = [marker]
      node = marker
      while node && node != body
        sibling = node.next_sibling
        while sibling
          quoted << sibling
          sibling = sibling.next_sibling
        end
        node = node.parent
      end
      quoted.each(&:unlink)
      return [body.inner_html + quoted.map(&:to_html).join, nil] if body.text.tr(" ", " ").strip.empty?

      [body.inner_html, quoted.map(&:to_html).join]
    end

    def self.quote_marker(body)
      order = body.xpath(".//*").each_with_index.to_h
      candidates = body.css(QUOTE_SELECTORS).to_a
      candidates << text_marker(body)
      marker = candidates.compact.min_by { |node| order.fetch(node, Float::INFINITY) }
      return unless marker

      attribution_before(marker) || marker
    end

    # « Le 19 oct. 2026 à 07:49, X <x@y> a écrit : », « -----Original Message----- »,
    # ou un en-tête Outlook « De : … Envoyé : … » : l'élément le plus profond
    # qui le porte seul.
    def self.text_marker(body)
      found = body.xpath(".//*").find { |node| attribution_node?(node) }
      return unless found

      found = found.element_children.find { |child| attribution_node?(child) } while found.element_children.any? { |child| attribution_node?(child) }
      separator = found.previous_element
      separator&.name == "hr" ? separator : found
    end

    def self.attribution_node?(node)
      text = node.text.tr(" ", " ").strip
      return false if text.empty? || text.length > 600

      text.match?(ATTRIBUTION) || text.match?(SEPARATOR) || (text.match?(HEADER_FROM) && text.match?(HEADER_NEXT))
    end

    # Apple Mail et Yahoo posent « … a écrit : » en texte nu juste avant le
    # <blockquote> : il part avec la citation.
    def self.attribution_before(marker)
      previous = marker.previous_sibling
      previous = previous.previous_sibling while previous&.text? && previous.text.strip.empty?
      previous if previous && previous.text.tr(" ", " ").strip.match?(WROTE) && previous.text.length < 600
    end

    def self.text_quote_start(lines)
      lines.each_with_index do |line, i|
        stripped = line.strip
        start = if stripped.match?(SEPARATOR)
                  i
                elsif stripped.match?(WROTE) && stripped.length < 400
                  i.positive? && !stripped.match?(/\A(Le|On|Am|Op|El|Il)\s/) && lines[i - 1].strip.match?(/\A(Le|On|Am|Op|El|Il)\s/) ? i - 1 : i
                elsif stripped.match?(HEADER_FROM) && lines[(i + 1)..(i + 4)].to_a.any? { |l| l.match?(HEADER_NEXT) }
                  i.positive? && lines[i - 1].strip.match?(/\A_{10,}\z/) ? i - 1 : i
                elsif stripped.start_with?(">")
                  i
                end
        next unless start
        return nil if lines[0...start].join.strip.empty?

        return start
      end
      nil
    end

    def self.sanitize(html)
      clean = Rails::HTML5::SafeListSanitizer.new.sanitize(html.to_s, tags: TAGS, attributes: ATTRIBUTES)
      fragment = Nokogiri::HTML5.fragment(clean)
      fragment.css("a").each do |link|
        if link["href"].to_s.match?(%r{\A(https?:|mailto:)}i)
          link["target"] = "_blank"
          link["rel"] = "noopener noreferrer nofollow"
        else
          link.remove_attribute("href")
        end
      end
      trim_edges(fragment)
      fragment.to_html
    end

    # Les lignes vides (<br>, <div>&nbsp;</div>) en tête et en fin de message,
    # jusque dans les <div> qui l'enveloppent.
    def self.trim_edges(node, sides = %i[first last])
      sides.each do |side|
        loop do
          edge = side == :first ? node.children.first : node.children.last
          break unless edge

          if blank_node?(edge)
            edge.remove
          else
            trim_edges(edge, [side]) if edge.element? && %w[div blockquote].include?(edge.name)
            break
          end
        end
      end
    end

    def self.blank_node?(node)
      return node.text.tr(" ", " ").strip.empty? if node.text?
      return true if node.name == "br"

      node.element? && %w[p div span].include?(node.name) && node.text.tr(" ", " ").strip.empty? &&
        node.css("hr, table").empty?
    end

    def self.text_of_html(html) = Nokogiri::HTML5.fragment(html.to_s).text.tr(" ", " ").strip

    private_class_method :html_source, :plain_source, :utf8, :legacy_text, :tidy, :parse, :split,
                         :quote_marker, :text_marker, :attribution_node?, :attribution_before,
                         :text_quote_start, :sanitize, :trim_edges, :blank_node?, :text_of_html
  end
end
