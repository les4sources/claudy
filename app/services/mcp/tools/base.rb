module Mcp
  module Tools
    # Un outil MCP : un nom, une description que Claude lit pour savoir quand
    # s'en servir, un schéma d'arguments, et `call` qui rend du texte.
    #
    # Le texte est fait pour être lu — par Claude, puis par l'humain à qui il
    # le montre. Les identifiants (#3365) y figurent toujours : c'est eux qu'un
    # outil d'écriture prend ensuite en argument.
    class Base
      # Une erreur que l'utilisateur peut corriger (compte introuvable, date
      # illisible…). Rendue à Claude telle quelle, sans trace côté Sentry.
      class Error < StandardError; end

      class << self
        attr_reader :tool_name, :title, :description, :input_schema

        def tool(name, title:, description:, schema:)
          @tool_name = name
          @title = title
          @description = description
          @input_schema = { type: "object", additionalProperties: false }.merge(schema)
        end

        def read_only? = true

        def definition
          {
            name: tool_name,
            title: title,
            description: description,
            inputSchema: input_schema,
            annotations: { title: title, readOnlyHint: read_only?, destructiveHint: !read_only?,
                           idempotentHint: read_only?, openWorldHint: false }
          }
        end
      end

      # Schémas d'arguments réutilisés d'un outil à l'autre.
      COMPTE = { type: "string", description: "Code du compte (SRC-0002), ou partie de son nom ou du nom du ménage (Frennet)." }.freeze
      POSTE = {
        type: "string",
        description: "Poste : bar, grocery (épicerie), meal (repas), pot (cagnotte), dome, pet (animaux), " \
                     "charges ou other (divers). Le libellé français est accepté."
      }.freeze
      DATE = { type: "string", format: "date", description: "Date ISO, AAAA-MM-JJ." }.freeze

      def initialize(user:)
        @user = user
      end

      def call(_arguments)
        raise NotImplementedError
      end

      private

      attr_reader :user

      def euros(cents)
        "#{format('%.2f', cents.to_i / 100.0).tr('.', ',')} €"
      end

      # Un compte par son code exact, ou par son nom. Plusieurs candidats : on
      # refuse et on les liste, plutôt que d'écrire sur le mauvais compte.
      def compte!(reference)
        reference = reference.to_s.strip
        raise Error, "Précise le compte (code SRC-… ou nom)." if reference.empty?

        par_code = MemberAccount.find_by(code: reference.upcase)
        return par_code if par_code

        motif = "%#{MemberAccount.sanitize_sql_like(reference)}%"
        candidats = MemberAccount.left_joins(:household)
                                 .where("member_accounts.name ILIKE :m OR households.name ILIKE :m", m: motif)
                                 .order("member_accounts.name").to_a
        exact = candidats.select { |compte| compte.name.casecmp?(reference) }
        candidats = exact if exact.size == 1
        return candidats.first if candidats.size == 1

        raise Error, "Aucun compte ne correspond à « #{reference} »." if candidats.empty?

        raise Error, "Plusieurs comptes correspondent à « #{reference} » : " \
                     "#{candidats.first(10).map { |c| "#{c.code} #{c.name}" }.join(', ')}. Précise le code."
      end

      def poste!(valeur)
        cle = I18n.transliterate(valeur.to_s.strip).downcase
        return cle if AccountEntry::FLOWS.include?(cle)

        trouve = AccountEntry::FLOW_LABELS.find { |_, label| I18n.transliterate(label).downcase == cle }&.first
        trouve || raise(Error, "Poste inconnu : « #{valeur} ». Postes : #{AccountEntry::FLOWS.join(', ')}.")
      end

      def date!(valeur, champ)
        Date.iso8601(valeur.to_s)
      rescue ArgumentError, Date::Error
        raise Error, "#{champ} : date illisible « #{valeur} » (format attendu AAAA-MM-JJ)."
      end

      def date_ou_nil(valeur, champ)
        valeur.blank? ? nil : date!(valeur, champ)
      end

      # « 92,17 », « 92.17 » ou 92.17 → 9217. Le signe est gardé.
      def cents!(valeur, champ)
        texte = valeur.to_s.strip.delete(" €").tr(",", ".")
        raise Error, "#{champ} : montant illisible « #{valeur} »." unless texte.match?(/\A-?\d+(\.\d{1,2})?\z/)

        cents = (BigDecimal(texte) * 100).to_i
        raise Error, "#{champ} : un montant nul n'a pas de sens." if cents.zero?

        cents
      end

      def ids!(valeur)
        ids = Array(valeur).map { |id| Integer(id.to_s.delete("#")) }
        raise Error, "Donne au moins un identifiant de ligne." if ids.empty?

        ids.uniq
      rescue ArgumentError
        raise Error, "Identifiants de ligne illisibles : #{Array(valeur).join(', ')}."
      end

      def ligne(entry)
        verrou = entry.locked? ? " [VERROUILLÉE : décompte émis]" : ""
        reference = entry.account_settlement&.reference.presence
        "##{entry.id}  #{entry.entry_date}  #{euros(entry.amount_cents).rjust(11)}  " \
          "#{entry.flow_label || '—'} · #{entry.kind_label || '—'}  #{entry.label}" \
          "#{" « #{reference} »" if reference}#{verrou}"
      end
    end
  end
end
