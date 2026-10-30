module SalesInvoices
  # Mettre au registre une facture dont l'écriture de vente existe déjà
  # (Michael, 2026-10-30) : les pièces 2026 reprises de Winbooks
  # (« 2026:VENTES:2026-078 ») et celles passées à la main au journal Ventes
  # (fondation, « Ventes 2026/1 » à « 2026/83 »).
  #
  # La facture POINTE l'écriture, elle ne la passe pas : la recette est déjà au
  # grand livre, la repasser la compterait deux fois. Tiers, total, type et
  # lignes se lisent sur l'écriture (le 400000 et son tiers, les comptes 7, le
  # 451000) ; ce qu'on donne en plus doit lui correspondre.
  #
  # Les encaissements déjà imputés sur le 400000 de ce tiers sont ensuite
  # reliés à la facture, sans rien réécrire : ceux dont la ligne cite le
  # numéro, sinon le seul du montant exact — et seulement si aucune autre vente
  # de ce tiers n'a le même montant, sans quoi on ne sait pas laquelle il paie.
  class AttachEntry < ServiceBase
    class Refused < StandardError; end

    CUSTOMER_PREFIX = "40".freeze
    VAT_PREFIX = "451".freeze

    attr_reader :invoice, :linked_allocations, :warnings

    # `attributes` : number, issued_on, third_party_id, kind,
    # credited_invoice_id, notes, et éventuellement
    # sales_invoice_lines_attributes (sinon lues sur l'écriture).
    def initialize(journal_entry:, attributes: {}, document: nil, link_payments: true, whodunnit: nil)
      @entry = journal_entry
      @attributes = attributes.to_h.stringify_keys.compact_blank
      @document = document
      @link_payments = link_payments
      @whodunnit = whodunnit
      @linked_allocations = []
      @warnings = []
    end

    def run = catch_error(context: { journal_entry: @entry&.id }) { attach }
    def run! = attach

    # L'écriture de vente que désigne une référence, chez une entité :
    # « #123 » (id), « Ventes 2026/72 » ou « 2026/72 » (numéro au journal), la
    # référence de la pièce reprise (« 2026:VENTES:2026-078 ») ou le numéro de
    # facture en tête du libellé (« 2026-078 »).
    def self.entries_for(legal_entity:, reference:)
      texte = reference.to_s.strip
      return JournalEntry.none if texte.empty?

      ventes = JournalEntry.where(journal: "sales")
      ventes = ventes.where(legal_entity: legal_entity) if legal_entity
      return ventes.where(id: texte.delete("#")) if texte.match?(/\A#\d+\z/)

      if (m = texte.match(%r{\A(?:ventes\s+)?(\d{4})/(\d+)\z}i))
        return ventes.joins(:fiscal_year).where(number: m[2].to_i)
                     .where("EXTRACT(YEAR FROM fiscal_years.starts_on) = ?", m[1].to_i)
      end

      reprises = ventes.where(source_type: "LedgerDocument",
                              source_id: LedgerDocument.where("external_ref = :r OR external_ref LIKE :fin",
                                                              r: texte, fin: "%:#{LedgerDocument.sanitize_sql_like(texte)}").select(:id))
      return reprises if reprises.exists?

      ventes.where("journal_entries.label ~* ?", "^#{Regexp.escape(texte)}([^[:alnum:]-]|$)")
    end

    # Les écritures de vente d'une entité qui attendent encore leur facture :
    # ni contre-passées, ni contre-passation, ni déjà pointées par une facture,
    # et passées au compte clients.
    def self.attachable(legal_entity:, from:, to:)
      JournalEntry.where(journal: "sales", legal_entity: legal_entity, entry_date: from..to, reversal_of_id: nil)
                  .where.not(id: JournalEntry.where.not(reversal_of_id: nil).select(:reversal_of_id))
                  .where.not(id: SalesInvoice.where.not(journal_entry_id: nil).select(:journal_entry_id))
                  .where("journal_entries.source_type IS NULL OR journal_entries.source_type <> 'SalesInvoice'")
                  .where(id: JournalLine.joins(:general_account)
                                        .where("general_accounts.code LIKE ?", "#{CUSTOMER_PREFIX}%").select(:journal_entry_id))
                  .order(:entry_date, :number)
    end

    Preview = Struct.new(:entry, :number, :third_party, :total_cents, :kind, :error, keyword_init: true) do
      def ready? = error.nil? && number.present? && third_party.present?
    end

    # Ce que le rattachement lirait sur l'écriture, sans rien écrire.
    def preview
      check_entry!
      lecture = read_entry
      Preview.new(entry: @entry, number: @attributes["number"].presence || numero_du_libelle,
                  third_party: lecture.third_party, total_cents: lecture.total_cents, kind: lecture.kind)
    rescue Refused => e
      Preview.new(entry: @entry, error: e.message)
    end

    private

    def attach
      check_entry!
      lecture = read_entry

      PaperTrail.request(whodunnit: @whodunnit || "sales_invoice_attach") do
        ApplicationRecord.transaction do
          @invoice = SalesInvoice.new(invoice_attributes(lecture))
          @invoice.save!
          @invoice.document.attach(@document) if @document.present?

          link_payments(lecture) if @link_payments
          RefreshPayment.new(sales_invoice: @invoice).run!
          RefreshPayment.new(sales_invoice: @invoice.credited_invoice).run! if @invoice.credited_invoice
        end
      end

      @invoice.reload
    end

    def check_entry!
      raise Refused, "Donne l'écriture de vente à rattacher." if @entry.blank?
      raise Refused, "#{@entry.reference} n'est pas au journal Ventes." unless @entry.journal == "sales"
      raise Refused, "#{@entry.reference} est une contre-passation." if @entry.reversal_of_id
      raise Refused, "#{@entry.reference} a été contre-passée." if @entry.reversal.present?

      deja = SalesInvoice.find_by(journal_entry_id: @entry.id)
      deja ||= SalesInvoice.find_by(id: @entry.source_id) if @entry.source_type == "SalesInvoice"
      raise Refused, "#{@entry.reference} est déjà celle de la #{deja.label.downcase_first} (##{deja.id})." if deja
    end

    Lecture = Struct.new(:kind, :total_cents, :third_party, :customer_account_ids, :revenue, :vat_cents, keyword_init: true)

    # Ce que dit l'écriture. Débit au 400000 : une facture ; crédit : une note
    # de crédit. Toute autre ligne qu'un 400000, un compte 7 ou un 451000 rend
    # la lecture des lignes impossible : il faut alors les donner.
    def read_entry
      lignes = @entry.journal_lines.includes(:general_account, :third_party).to_a
      clients = lignes.select { |l| l.general_account.code.start_with?(CUSTOMER_PREFIX) }
      raise Refused, "#{@entry.reference} ne passe rien au compte clients (400000) : ce n'est pas une facture." if clients.empty?

      solde = clients.sum { |l| l.debit_cents - l.credit_cents }
      raise Refused, "#{@entry.reference} solde le compte clients à zéro." if solde.zero?

      kind = solde.positive? ? "invoice" : "credit_note"
      sens = solde.positive? ? 1 : -1
      tiers = clients.filter_map(&:third_party).uniq
      raise Refused, "#{@entry.reference} passe le 400000 sur plusieurs tiers (#{tiers.map(&:name).join(', ')})." if tiers.size > 1

      produits = lignes.select { |l| l.general_account.klass == 7 }
      tva = lignes.select { |l| l.general_account.code.start_with?(VAT_PREFIX) }
      autres = lignes - clients - produits - tva

      Lecture.new(
        kind: kind, total_cents: solde.abs, third_party: tiers.first,
        customer_account_ids: clients.map(&:general_account_id).uniq,
        revenue: autres.empty? ? produits.map { |l| [l, sens * (l.credit_cents - l.debit_cents)] }.reject { |_, n| n.zero? } : nil,
        vat_cents: sens * tva.sum { |l| l.credit_cents - l.debit_cents }
      )
    end

    def invoice_attributes(lecture)
      kind = @attributes["kind"].presence || lecture.kind
      raise Refused, "#{@entry.reference} est une #{lecture.kind == 'invoice' ? 'facture' : 'note de crédit'}, pas une #{kind == 'invoice' ? 'facture' : 'note de crédit'}." if kind != lecture.kind

      if @attributes["total_cents"].present? && @attributes["total_cents"].to_i.abs != lecture.total_cents
        raise Refused, "#{@entry.reference} porte #{Money.new(lecture.total_cents, 'EUR').format} au 400000, " \
                       "pas #{Money.new(@attributes['total_cents'].to_i.abs, 'EUR').format}."
      end

      numero = @attributes["number"].presence || numero_du_libelle ||
               raise(Refused, "Le libellé de #{@entry.reference} (« #{@entry.label} ») ne donne pas de numéro de facture : donne-le.")
      tiers = third_party(lecture)

      @attributes.except("total_cents", "kind", "third_party_id", "sales_invoice_lines_attributes").merge(
        "legal_entity_id" => @entry.legal_entity_id, "third_party_id" => tiers.id, "kind" => kind,
        "number" => numero, "issued_on" => @attributes["issued_on"].presence || @entry.entry_date,
        "total_cents" => lecture.total_cents, "status" => "issued", "posting_mode" => "on_issue",
        "journal_entry_id" => @entry.id, "posted_at" => @entry.posted_at || Time.current,
        "sales_invoice_lines_attributes" => @attributes["sales_invoice_lines_attributes"].presence || lines_from(lecture)
      )
    end

    def third_party(lecture)
      donne = ThirdParty.find(@attributes["third_party_id"]) if @attributes["third_party_id"].present?
      if donne && lecture.third_party && donne != lecture.third_party
        raise Refused, "#{@entry.reference} passe le 400000 sur #{lecture.third_party.name}, pas sur #{donne.name}."
      end

      donne || lecture.third_party ||
        raise(Refused, "#{@entry.reference} ne nomme pas de tiers sur le 400000 : donne le client.")
    end

    # « 2026-078 » ou « 2026-097 Bonsacquet Heidi - pains » : le premier mot,
    # s'il porte un chiffre.
    def numero_du_libelle
      premier = @entry.label.to_s.strip.split(/\s+/).first.to_s.delete_suffix(",")
      premier if premier.match?(/\d/) && premier.length >= 3
    end

    # Une ligne par compte 7 de l'écriture, la TVA répartie au prorata du HTVA.
    # Le taux est celui que la TVA totale donne, arrondi au taux belge le plus
    # proche : l'écriture ne le dit pas, la facture OkiOki si.
    def lines_from(lecture)
      if lecture.revenue.nil?
        raise Refused, "#{@entry.reference} porte d'autres comptes que le 400000, les comptes 7 et le 451000 : donne les lignes."
      end
      raise Refused, "#{@entry.reference} ne crédite aucun compte de produit (classe 7) : donne les lignes." if lecture.revenue.empty?

      net = lecture.revenue.sum(&:last)
      if net + lecture.vat_cents != lecture.total_cents
        raise Refused, "#{@entry.reference} ne s'équilibre pas entre 400000, produits et TVA : donne les lignes."
      end

      taux = net.zero? || lecture.vat_cents.zero? ? 0 : SalesInvoiceLine::VAT_RATES.min_by { |r| (r - lecture.vat_cents * 100.0 / net).abs }
      parts = lecture.revenue.map { |_, n| net.zero? ? 0 : (n * lecture.vat_cents).quo(net).round }
      parts[parts.each_index.max_by { |i| lecture.revenue[i].last.abs }] += lecture.vat_cents - parts.sum

      lecture.revenue.each_with_index.map do |(ligne, ht), index|
        { "general_account_id" => ligne.general_account_id, "label" => ligne.label.presence || @entry.label,
          "team_id" => ligne.team_id, "analytic_account_id" => ligne.analytic_account_id,
          "amount_cents" => ht + parts[index], "vat_cents" => parts[index], "vat_rate" => taux, "position" => index }
      end
    end

    # Les encaissements déjà au 400000 de ce tiers, pas encore reliés à une
    # pièce. D'abord ceux qui citent le numéro, puis le seul du montant exact
    # qui reste dû — si aucune autre vente de ce tiers n'a ce montant.
    def link_payments(lecture)
      sortant = @invoice.credit_note?
      candidats = CashAllocation.where(document_id: nil, third_party_id: @invoice.third_party_id,
                                       legal_entity_id: @invoice.legal_entity_id,
                                       general_account_id: lecture.customer_account_ids)
                                .where(sortant ? "cash_allocations.amount_cents < 0" : "cash_allocations.amount_cents > 0")
                                .includes(:cash_entry).joins(:cash_entry)
                                .order("cash_entries.entry_date, cash_allocations.id").to_a
      reste = @invoice.remaining_cents

      cites = candidats.select do |a|
        [a.label, a.cash_entry.label, a.cash_entry.try(:communication)].any? { |t| Finance::MatchSalesInvoices.cites?(t, @invoice.number) }
      end
      cites.each do |allocation|
        break unless reste.positive?

        if allocation.amount_cents.abs > reste
          @warnings << "#{entry_ref(allocation)} cite #{@invoice.number} mais porte #{Money.new(allocation.amount_cents.abs, 'EUR').format} " \
                       "pour #{Money.new(reste, 'EUR').format} dû : non relié."
          next
        end
        relier(allocation)
        reste -= allocation.amount_cents.abs
      end
      return unless reste.positive? && cites.empty?

      exacts = candidats.select { |a| a.amount_cents.abs == reste }
      return if exacts.empty?

      if exacts.size > 1
        @warnings << "#{exacts.size} encaissements de #{Money.new(reste, 'EUR').format} pour #{@invoice.third_party.name} " \
                     "(#{exacts.map { |a| entry_ref(a) }.join(', ')}) : aucun relié, rapproche le bon à la main."
      elsif same_amount_sales?(lecture)
        @warnings << "#{entry_ref(exacts.first)} (#{Money.new(reste, 'EUR').format}) peut payer une autre vente du même montant " \
                     "à #{@invoice.third_party.name} : non relié, rapproche-le à la main."
      else
        relier(exacts.first)
      end
    end

    def relier(allocation)
      allocation.relink_document!(@invoice)
      @linked_allocations << allocation
    end

    # Une autre écriture de vente au même tiers et au même montant : le
    # virement peut payer l'une comme l'autre.
    def same_amount_sales?(lecture)
      JournalLine.joins(:journal_entry)
                 .where(journal_entries: { journal: "sales", legal_entity_id: @entry.legal_entity_id, reversal_of_id: nil })
                 .where.not(journal_entry_id: @entry.id)
                 .where(general_account_id: lecture.customer_account_ids, third_party_id: @invoice.third_party_id)
                 .where(@invoice.credit_note? ? { credit_cents: @invoice.total_cents } : { debit_cents: @invoice.total_cents })
                 .where.not(journal_entry_id: JournalEntry.where.not(reversal_of_id: nil).select(:reversal_of_id))
                 .exists?
    end

    def entry_ref(allocation)
      "ligne ##{allocation.cash_entry_id} du #{I18n.l(allocation.cash_entry.entry_date)}"
    end
  end
end
