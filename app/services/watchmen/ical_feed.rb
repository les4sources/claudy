module Watchmen
  # Flux iCalendar (RFC 5545) des gardes — rôle « Veilleur·euse » (issue #142).
  #
  # Abonnable depuis Google Agenda (« Ajouter depuis l'URL ») : Google refait la
  # requête tout seul, à son rythme. D'où deux exigences structurantes :
  #
  #   - un `UID` STABLE par jour, dérivé de la date : une re-synchronisation doit
  #     METTRE À JOUR l'événement existant, jamais en créer un doublon ;
  #   - un rendu DÉTERMINISTE (noms triés, événements triés par date) : deux
  #     générations sur les mêmes données donnent le même flux à l'octet près.
  #
  # Strictement en LECTURE : rien n'est écrit, rien n'est modifié.
  class IcalFeed
    # Il n'existe qu'un seul rôle dans Claudy : #1 « Veilleur·euse » — la garde.
    # Même convention que `HumanRole#has_watchman_note?` et `PagesController`.
    WATCHMAN_ROLE_ID = 1

    PRODID = "-//Les 4 Sources//Claudy Gardes//FR".freeze
    CALENDAR_NAME = "Gardes — Les 4 Sources".freeze

    # Domaine des UID : une CONSTANTE, jamais l'hôte configuré. Si l'hôte de
    # l'app changeait, des UID dérivés de l'hôte changeraient aussi et Google
    # recréerait tous les événements en double.
    UID_DOMAIN = "claudy.les4sources.be".freeze

    # Plusieurs personnes le même jour → un seul événement, noms joints.
    NAME_SEPARATOR = " & ".freeze

    # La RFC 5545 exige des fins de ligne CRLF et des lignes de 75 octets max
    # (au-delà : pliage sur une ligne de continuation commençant par une espace).
    CRLF = "\r\n".freeze
    MAX_LINE_OCTETS = 75

    # `DTSTAMP` est obligatoire dans un VEVENT. On le dérive du `updated_at` des
    # gardes du jour pour qu'il reste stable tant que la garde ne bouge pas.
    FALLBACK_DTSTAMP = Time.utc(2000, 1, 1).freeze

    MissingHostError = Class.new(StandardError)

    Day = Struct.new(:date, :names, :updated_at)

    def to_ics
      lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:#{escape_text(PRODID)}",
        "CALSCALE:GREGORIAN",
        "X-WR-CALNAME:#{escape_text(CALENDAR_NAME)}"
      ]
      days.each { |day| lines.concat(vevent_lines(day)) }
      lines << "END:VCALENDAR"

      lines.flat_map { |line| fold(line) }.join(CRLF) + CRLF
    end

    # Un élément par JOUR ayant au moins une garde titulaire, trié par date.
    def days
      @days ||= begin
        names = names_by_human_id(assignments.map { |row| row[1] }.uniq)

        assignments.group_by { |row| row[0] }.sort_by(&:first).filter_map do |date, rows|
          day_names = sort_names(rows.filter_map { |row| names[row[1]] }.uniq)
          next if day_names.empty?

          Day.new(date, day_names, rows.filter_map { |row| row[2] }.max)
        end
      end
    end

    private

    # Toutes les gardes connues — pas de fenêtre glissante : le volume est faible
    # (~1150 événements) et l'historique est utile. Seuls les TITULAIRES
    # (`status: selected`) sortent ; les `backup` ne produisent aucun événement.
    # UNE seule requête pour l'ensemble du flux.
    def assignments
      @assignments ||= HumanRole
        .where(role_id: WATCHMAN_ROLE_ID, status: :selected)
        .where.not(date: nil)
        .pluck(:date, :human_id, :updated_at)
    end

    # `Human` porte un `default_scope` (`status: "active"` + soft-deletion). Un
    # `includes(:human)` ferait donc DISPARAÎTRE les gardes des membres devenus
    # inactifs : sur les données de production, 52 jours sont concernés, dont 37
    # où la personne est seule — autant d'événements sans nom. Le flux est un
    # historique de qui était de garde : on lit les noms hors `default_scope`, en
    # UNE requête (aucun N+1).
    def names_by_human_id(human_ids)
      return {} if human_ids.empty?

      Human.unscoped.where(id: human_ids).pluck(:id, :name).to_h
    end

    # Ordre alphabétique insensible aux accents (« Émile » avant « Fred », et non
    # après « Zoé »), avec le nom brut en second critère : le tri est total, donc
    # le rendu est stable d'une génération à l'autre.
    def sort_names(names)
      names.sort_by { |name| [I18n.transliterate(name).downcase, name] }
    end

    def vevent_lines(day)
      [
        "BEGIN:VEVENT",
        "UID:#{uid_for(day.date)}",
        "DTSTAMP:#{ical_timestamp(day.updated_at)}",
        # Événement all-day. Le `DTEND` d'un all-day iCal est EXCLUSIF : sans le
        # +1 jour, Google affiche une durée nulle ou décale l'événement.
        "DTSTART;VALUE=DATE:#{ical_date(day.date)}",
        "DTEND;VALUE=DATE:#{ical_date(day.date + 1)}",
        "SUMMARY:#{escape_text(summary_for(day))}",
        # `URL` est de type URI, pas TEXT : la RFC ne lui applique pas
        # l'échappement `\;` / `\,`. La valeur vient des url_helpers Rails.
        "URL:#{calendar_url_for(day.date)}",
        # Google Agenda n'affiche pas toujours la propriété `URL` seule : on
        # rappelle le lien dans la DESCRIPTION, elle-même de type TEXT.
        "DESCRIPTION:#{escape_text(description_for(day))}",
        "END:VEVENT"
      ]
    end

    def summary_for(day)
      "Garde : #{day.names.join(NAME_SEPARATOR)}"
    end

    def description_for(day)
      [summary_for(day), "Calendrier Claudy : #{calendar_url_for(day.date)}"].join("\n")
    end

    def uid_for(date)
      "garde-#{date.strftime('%Y%m%d')}@#{UID_DOMAIN}"
    end

    def ical_date(date)
      date.strftime("%Y%m%d")
    end

    def ical_timestamp(time)
      (time || FALLBACK_DTSTAMP).utc.strftime("%Y%m%dT%H%M%SZ")
    end

    # Lien vers le calendrier Claudy AU MOIS de la garde : la page racine accepte
    # `?date=AAAA-MM-JJ` (cf. `PagesController#set_dates`).
    def calendar_url_for(date)
      Rails.application.routes.url_helpers.root_url(
        **url_options, date: date.beginning_of_month.iso8601
      )
    end

    # L'hôte vient de la configuration de l'app (celle des emails), jamais d'une
    # valeur codée en dur.
    def url_options
      @url_options ||= begin
        options = (Rails.application.config.action_mailer.default_url_options || {}).symbolize_keys

        if options[:host].blank?
          raise MissingHostError,
                "config.action_mailer.default_url_options[:host] est requis pour générer le flux iCal des gardes."
        end

        options.slice(:host, :port, :protocol).compact
      end
    end

    # Échappement RFC 5545 des valeurs TEXT. L'antislash PASSE EN PREMIER, sinon
    # on ré-échapperait les antislashs qu'on vient d'introduire. La forme à bloc
    # de `gsub` est volontaire : elle n'interprète pas les `\\` du remplacement.
    def escape_text(text)
      text.to_s
          .gsub(/[\\;,]/) { |char| "\\#{char}" }
          .gsub(/\r\n|\r|\n/) { "\\n" }
    end

    # Pliage RFC 5545 : 75 octets max par ligne, continuation préfixée d'une
    # espace. On découpe par CARACTÈRE en comptant les octets, pour ne jamais
    # couper une séquence UTF-8 en deux (« — », « é »…).
    def fold(line)
      return [line] if line.bytesize <= MAX_LINE_OCTETS

      chunks = []
      current = +""
      limit = MAX_LINE_OCTETS

      line.each_char do |char|
        if current.bytesize + char.bytesize > limit
          chunks << current
          current = +""
          # Les lignes de continuation commencent par une espace, qui compte
          # dans les 75 octets : il reste 74 octets de contenu.
          limit = MAX_LINE_OCTETS - 1
        end
        current << char
      end
      chunks << current

      chunks.each_with_index.map { |chunk, index| index.zero? ? chunk : " #{chunk}" }
    end
  end
end
