module Finance
  # Demande à Jev le compte d'une ligne de trésorerie qu'aucune règle ne couvre.
  #
  # Jev ne choisit que parmi les comptes que `AllocationHistory` lui présente,
  # avec pour chacun quelques lignes typiques, et il voit comment la compta a
  # affecté des lignes semblables. Il ne peut donc pas inventer de compte : au
  # pire il se trompe de candidat, et un humain refuse.
  #
  # Mesuré sur 150 lignes 2025 sans règle, avec l'historique 2022-2024 : 71 %
  # de réponses justes, 92 % au-dessus de 0,8 de confiance, où il couvre deux
  # lignes sur trois. En dessous du seuil, on ne propose RIEN — une proposition
  # douteuse coûte plus cher qu'une absence de proposition, parce qu'on finit
  # par l'accepter de confiance.
  class JevSuggestion
    MIN_CONFIDENCE = 0.8
    NONE = "aucun".freeze
    SHOWN_NEIGHBOURS = 8

    QUESTION = {
      question: "À quel compte comptable faut-il affecter cette ligne de trésorerie (`ligne`) de la Fondation " \
                "Les 4 Sources, un tiers-lieu (gîtes, bar, épicerie, boulangerie, ateliers) ?",
      focus: "Juge d'après la contrepartie, la communication, le sens et le montant de `ligne`. " \
             "`lignes_semblables_deja_affectees` et `historique_meme_contrepartie` montrent comment la " \
             "comptabilité a affecté des lignes proches ; une même personne peut payer des choses différentes."
    }.freeze

    def initialize(cash_entry:, jev:, history: AllocationHistory.current)
      @entry = cash_entry
      @jev = jev
      @history = history
    end

    # Rend une suggestion NON enregistrée, ou nil. Lève `Jev::Client::Error`
    # quand Jev est injoignable : l'appelant décide s'il réessaiera.
    def call
      return nil if @history.empty?

      neighbours = @history.neighbours(@entry)
      same = @history.same_counterparty(@entry)
      accounts = GeneralAccount.where(id: @history.candidate_account_ids(@entry, neighbours: neighbours, same: same),
                                      active: true).index_by(&:id)
      return nil if accounts.empty?

      options = accounts.values.to_h { |account| [account.to_s, account] }
      answer = @jev.ask(state: state(neighbours, same, accounts), questions: { "compte" => question(options) })["compte"]
      return nil if answer.nil?

      account = options[answer["choice"]]
      confidence = answer["confidence"].to_f
      return nil if account.nil? || confidence < MIN_CONFIDENCE

      @entry.allocation_suggestions.new(
        general_account: account,
        legal_entity: @entry.cash_account.legal_entity,
        amount_cents: @entry.remaining_cents,
        confidence: (confidence * 100).floor,
        source: "jev",
        rationale: rationale(account, neighbours, same)
      )
    end

    private

    def question(options)
      criteria = options.to_h do |key, account|
        [key, { what: "Compte #{key}", examples: @history.examples_for(account.id) }]
      end
      { type: "choice", instructions: QUESTION, criteria: criteria.merge(NONE => "Aucun de ces comptes ne convient.") }
    end

    def state(neighbours, same, accounts)
      {
        "ligne" => describe(@entry.entry_date, @entry.amount_cents, @entry.counterparty_name,
                            @entry.communication.presence || @entry.label).merge("support" => support),
        "lignes_semblables_deja_affectees" => neighbours.first(SHOWN_NEIGHBOURS).map { |n| precedent(n.precedent, accounts) },
        "historique_meme_contrepartie" => same.map { |p| precedent(p, accounts) }
      }
    end

    def precedent(p, accounts)
      describe(p.entry_date, p.amount_cents, p.counterparty_name, p.communication.presence || p.label)
        .merge("compte" => accounts[p.general_account_id]&.to_s || "compte #{p.general_account_id}")
    end

    # Jamais d'IBAN : Jev n'en a pas besoin pour juger, et il n'a pas à le lire.
    def describe(date, amount_cents, name, text)
      { "date" => date.iso8601,
        "montant" => Money.new(amount_cents, "EUR").format,
        "sens" => amount_cents.positive? ? "encaissement" : "décaissement",
        "contrepartie" => name.presence,
        "communication" => text.presence }
    end

    def support = @entry.cash_account.kind == "cash" ? "caisse (espèces)" : @entry.cash_account.name

    # Le motif est écrit par le CODE, à partir de ce que Jev a vu : un humain
    # juge la proposition sur des faits, pas sur une phrase générée.
    def rationale(account, neighbours, same)
      semblables = neighbours.first(SHOWN_NEIGHBOURS).map(&:precedent).select { |p| p.general_account_id == account.id }
      memes = same.select { |p| p.general_account_id == account.id }
      faits = []
      if semblables.any?
        exemple = semblables.first
        texte = [exemple.counterparty_name, exemple.communication.presence || exemple.label].compact_blank.join(" · ")
        faits << if semblables.one?
                   "une ligne semblable déjà affectée à ce compte, « #{texte.truncate(60)} » le #{I18n.l(exemple.entry_date)}"
                 else
                   "#{semblables.size} lignes semblables déjà affectées à ce compte, " \
                     "dont « #{texte.truncate(60)} » le #{I18n.l(exemple.entry_date)}"
                 end
      end
      faits << contrepartie(memes.size, same.size) if memes.any?
      faits << "choisi parmi les comptes habituels de ce sens" if faits.empty?
      "Jev : #{faits.join(' ; ')}."
    end

    def contrepartie(memes, total)
      return "la dernière ligne de cette contrepartie aussi" if total == 1
      return "les #{total} dernières lignes de cette contrepartie aussi" if memes == total

      "#{memes} des #{total} dernières lignes de cette contrepartie"
    end
  end
end
