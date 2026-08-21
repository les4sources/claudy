module Accounting
  # Reprend un document comptable venu d'un système extérieur — une facture de
  # 2023 chez Winbooks, qui n'a aucun équivalent métier dans Claudy.
  #
  # C'est le seul cas où une écriture n'est pas produite par un document que
  # Claudy connaît. On ne relâche pas la règle pour autant : l'écriture reste
  # produite par un service, à partir d'un `LedgerDocument` qui matérialise la
  # pièce d'origine et rend la reprise rejouable sans la doubler.
  #
  # Le service ne crée jamais un compte ni un tiers qu'il ne trouve pas. Un
  # référentiel qui se complète tout seul pendant un import de 11 000 lignes
  # produit des comptes fantômes issus de fautes de frappe, qu'on découvre au
  # bilan six mois plus tard. Compte inconnu, import refusé, l'humain tranche.
  class ImportLedgerDocument < ServiceBase
    class UnbalancedDocument < StandardError; end
    class UnknownAccount < StandardError; end
    class UnknownThirdParty < StandardError; end

    # `lines` est un tableau de hash :
    #   { account_code:, debit_cents:, credit_cents:, label:,
    #     third_party_code:, analytic_account_code: }
    def initialize(legal_entity:, source_system:, external_ref:, journal:,
                   entry_date:, label:, lines:, payload: {}, whodunnit: nil)
      @legal_entity = legal_entity
      @source_system = source_system
      @external_ref = external_ref
      @journal = journal
      @entry_date = entry_date
      @label = label
      @lines = lines
      @payload = payload
      @whodunnit = whodunnit || "winbooks-import"
    end

    def run
      catch_error(context: { external_ref: @external_ref }) { import }
    end

    def run!
      import
    end

    private

    def import
      # L'équilibre se contrôle AVANT toute écriture en base. Un document
      # déséquilibré vient d'une erreur de lecture de la source, pas d'une
      # comptabilité fausse — on veut le voir, pas l'arrondir.
      check_balance!

      document = LedgerDocument.find_or_initialize_by(
        source_system: @source_system, external_ref: @external_ref
      )
      document.assign_attributes(document_date: @entry_date, label: @label, payload: @payload)
      document.save!

      PostDocument.new(
        legal_entity: @legal_entity,
        journal: @journal,
        entry_date: @entry_date,
        label: @label,
        lines: @lines.map { |line| resolve(line) },
        source: document,
        whodunnit: @whodunnit
      ).run!
    end

    def check_balance!
      debit = @lines.sum { |line| line[:debit_cents].to_i }
      credit = @lines.sum { |line| line[:credit_cents].to_i }
      return if debit == credit

      raise UnbalancedDocument,
            "#{@external_ref} : #{debit} au débit contre #{credit} au crédit, " \
            "écart de #{debit - credit} centimes."
    end

    def resolve(line)
      {
        account: account_for(line[:account_code]),
        third_party: third_party_for(line[:third_party_code]),
        analytic_account: analytic_for(line[:analytic_account_code]),
        debit_cents: line[:debit_cents].to_i,
        credit_cents: line[:credit_cents].to_i,
        label: line[:label]
      }
    end

    def account_for(code)
      accounts[code.to_s] ||
        raise(UnknownAccount, "#{@external_ref} : compte #{code} absent du plan comptable.")
    end

    def third_party_for(code)
      return nil if code.blank?

      third_parties[code.to_s] ||
        raise(UnknownThirdParty, "#{@external_ref} : tiers #{code} inconnu.")
    end

    def analytic_for(code)
      return nil if code.blank?

      analytics[code.to_s]
    end

    # Les référentiels sont chargés une fois par processus : un import de 1 400
    # documents ferait autrement 11 000 allers-retours pour relire le même plan
    # comptable.
    def accounts = self.class.cache[:accounts] ||= GeneralAccount.all.index_by(&:code)
    def third_parties = self.class.cache[:third_parties] ||= ThirdParty.all.index_by(&:code)
    def analytics = self.class.cache[:analytics] ||= AnalyticAccount.all.index_by(&:code)

    class << self
      def cache = @cache ||= {}
      def reset_cache! = @cache = {}
    end
  end
end
