module Finance
  # Ce que la compta a déjà décidé : les lignes de trésorerie comptabilisées et
  # le compte où chacune est allée. C'est la matière dont Jev tire ses options.
  #
  # Jev ne choisit que parmi ce que le code lui donne. Le travail est donc ici :
  # trouver, pour une nouvelle ligne, la dizaine de comptes plausibles. Mesuré
  # sur 2025 à partir de l'historique 2022-2024, le bon compte figure parmi ces
  # candidats dans 86 % des cas.
  #
  # Seules les lignes COMPTABILISÉES comptent : une affectation en cours n'est
  # pas encore une décision. Et seuls les comptes ACTIFS sont proposés — un
  # compte abandonné par la compta (700002, remplacé par 700004) a coûté à lui
  # seul huit erreurs sur cent cinquante lors de l'essai.
  class AllocationHistory
    MONTHS = 36
    NEIGHBOURS = 12
    SAME_COUNTERPARTY = 6
    FREQUENT = 8
    MAX_CANDIDATES = 20
    EXAMPLES_PER_ACCOUNT = 4

    Precedent = Data.define(:entry_id, :entry_date, :amount_cents, :counterparty_name, :communication,
                            :label, :iban, :general_account_id, :tokens)
    Neighbour = Data.define(:precedent, :score)

    # L'index se reconstruit quand une allocation change, pas à chaque ligne :
    # une page de cinquante lignes demande cinquante suggestions en parallèle.
    def self.current
      key = [CashAllocation.maximum(:updated_at), CashAllocation.count]
      mutex.synchronize do
        @current = nil if @current_key != key
        @current_key = key
        @current ||= build
      end
    end

    def self.mutex = @mutex ||= Mutex.new

    def self.reset! = mutex.synchronize { @current = nil }

    def self.build(since: MONTHS.months.ago.to_date)
      rows = CashAllocation.joins(:cash_entry, :general_account)
                           .where(cash_entries: { status: "allocated", deleted_at: nil })
                           .where(general_accounts: { active: true, deleted_at: nil })
                           .where(cash_entries: { entry_date: since.. })
                           .pluck("cash_entries.id", "cash_entries.entry_date", "cash_entries.amount_cents",
                                  "cash_entries.counterparty_name", "cash_entries.communication", "cash_entries.label",
                                  "cash_entries.counterparty_iban", "cash_allocations.general_account_id",
                                  "cash_allocations.amount_cents")

      # Une ligne ventilée sur plusieurs comptes compte pour son compte principal.
      precedents = rows.group_by(&:first).map do |_, allocations|
        id, date, amount, name, communication, label, iban, = allocations.first
        account_id = allocations.max_by { |row| row.last.abs }[7]
        Precedent.new(entry_id: id, entry_date: date, amount_cents: amount, counterparty_name: name,
                      communication: communication, label: label, iban: normalize_iban(iban),
                      general_account_id: account_id, tokens: tokenize(name, communication, label))
      end
      new(precedents)
    end

    def self.tokenize(*texts)
      I18n.transliterate(texts.compact.join(" ")).downcase.split(/[^a-z0-9]+/)
          .select { |token| token.length > 2 && token !~ /\A\d+\z/ }.to_set
    end

    def self.normalize_iban(iban) = iban.to_s.gsub(/\s+/, "").upcase.presence

    attr_reader :precedents

    def initialize(precedents)
      @precedents = precedents
      frequencies = Hash.new(0)
      precedents.each { |p| p.tokens.each { |token| frequencies[token] += 1 } }
      @idf = frequencies.transform_values { |n| Math.log(precedents.size.to_f / (1 + n)) }
      @by_iban = precedents.select(&:iban).group_by(&:iban)
    end

    def empty? = precedents.empty?

    # Les lignes passées qui ressemblent le plus à celle-ci : mots rares en
    # commun dans la contrepartie, la communication et le libellé, même sens,
    # un léger avantage à l'historique récent — un compte né l'an dernier ne
    # doit pas être noyé sous trois ans d'habitudes anciennes.
    def neighbours(entry, limit: NEIGHBOURS)
      tokens = self.class.tokenize(entry.counterparty_name, entry.communication, entry.label)
      return [] if tokens.empty?

      incoming = entry.amount_cents.positive?
      precedents.filter_map do |p|
        next if p.entry_id == entry.id || p.amount_cents.positive? != incoming

        shared = tokens & p.tokens
        next if shared.empty?

        recent = (entry.entry_date - p.entry_date).abs <= 365 ? 0.5 : 0
        Neighbour.new(precedent: p, score: shared.sum { |token| @idf.fetch(token, 0) } + recent)
      end.max_by(limit, &:score)
    end

    # Ce que la compta a fait des dernières lignes de la même contrepartie.
    # C'est un indice, jamais une proposition : un ménage paie le bar,
    # l'épicerie, le pain et ses charges depuis le même compte, et le dernier
    # précédent n'est juste qu'une fois sur deux.
    def same_counterparty(entry, limit: SAME_COUNTERPARTY)
      iban = self.class.normalize_iban(entry.counterparty_iban)
      return [] if iban.nil?

      @by_iban.fetch(iban, []).reject { |p| p.entry_id == entry.id }.max_by(limit, &:entry_date)
    end

    # Les comptes les plus fréquents de l'année écoulée, dans le même sens.
    def frequent_account_ids(entry, limit: FREQUENT)
      incoming = entry.amount_cents.positive?
      depuis = entry.entry_date - 365
      precedents.select { |p| p.amount_cents.positive? == incoming && p.entry_date >= depuis }
                .map(&:general_account_id).tally.max_by(limit, &:last).map(&:first)
    end

    def candidate_account_ids(entry, neighbours: self.neighbours(entry), same: same_counterparty(entry))
      (neighbours.map { |n| n.precedent.general_account_id } +
        same.map(&:general_account_id) +
        frequent_account_ids(entry)).uniq.first(MAX_CANDIDATES)
    end

    # Quelques lignes typiques d'un compte, les plus récentes : c'est ce qui dit
    # à Jev ce que « 701001 Bar » veut dire ici, mieux que son intitulé.
    def examples_for(account_id, limit: EXAMPLES_PER_ACCOUNT)
      examples_by_account.fetch(account_id, []).first(limit)
    end

    private

    def examples_by_account
      @examples_by_account ||= precedents.sort_by(&:entry_date).reverse.each_with_object({}) do |p, hash|
        texte = [p.counterparty_name, p.communication.presence || p.label].compact_blank.join(" · ").truncate(80)
        liste = (hash[p.general_account_id] ||= [])
        liste << texte if texte.present? && liste.size < EXAMPLES_PER_ACCOUNT && liste.exclude?(texte)
      end
    end
  end
end
