module Finance
  # Sème les motifs de caisse avec le vocabulaire réel de la feuille papier
  # (epic #243, phase 1). Idempotent : relancer ne crée pas de doublon et
  # n'écrase jamais un motif que la comptabilité a retouché.
  #
  # Les comptes cibles sont ceux du référentiel (`rake accounting:seed_reference`).
  # Un compte absent est SIGNALÉ, jamais créé : le plan comptable appartient au
  # comptable, pas à un seed. Le motif concerné n'est simplement pas créé, et la
  # tâche le dit — on ajoute le compte, on relance, c'est réglé.
  class SeedCashMotifs
    # Le compte de caisse comptable. Décision 1 : UNE seule caisse — deux caisses
    # qu'on mélange donnent deux écarts au lieu d'un.
    CASH_ACCOUNT_NAME = "Caisse centrale".freeze
    CASH_GENERAL_CODE = "570000".freeze
    DEFAULT_ENTITY    = "Fondation Les 4 Sources".freeze

    # [libellé, sens, code du compte général]. L'ordre EST la position : c'est
    # celui dans lequel les motifs apparaîtront dans la liste de saisie, du plus
    # fréquent au plus rare.
    MOTIFS = [
      ["Bar",                                  "in",  "700300"],
      ["Épicerie",                             "in",  "700300"],
      ["Cellier",                              "in",  "700300"],
      ["Hébergement camping",                  "in",  "700000"],
      ["Pains marché",                         "in",  "700200"],
      ["Marché Anhée",                         "in",  "700200"],
      ["Camembert party",                      "in",  "700200"],
      ["Volontariat – nettoyage (chèques ALE)", "out", "610000"],
      ["Volontariat – espaces verts",          "out", "610000"],
      ["Retrait bancaire",                     "in",  GeneralAccount::INTERNAL_TRANSFER_CODE],
      ["Dépôt en banque",                      "out", GeneralAccount::INTERNAL_TRANSFER_CODE],
      ["Note de frais payée en espèces",       "out", "440000"],
      ["Facture payée en espèces",             "out", "440000"]
    ].freeze

    Result = Struct.new(:created, :kept, :missing_accounts, :cash_account_created, keyword_init: true) do
      def to_s
        "#{created.size} motif(s) créé(s), #{kept.size} conservé(s)" \
          "#{", #{missing_accounts.size} compte(s) manquant(s)" if missing_accounts.any?}"
      end
    end

    def run
      result = Result.new(created: [], kept: [], missing_accounts: [], cash_account_created: false)
      entity = LegalEntity.find_by(name: DEFAULT_ENTITY) || LegalEntity.ordered.first

      if entity.nil?
        result.missing_accounts << "aucune entité juridique — lance d'abord `rake accounting:seed_reference`"
        return result
      end

      result.cash_account_created = ensure_cash_account!(entity)
      MOTIFS.each_with_index { |(label, direction, code), index| seed(label, direction, code, index + 1, entity, result) }
      result
    end

    private

    def seed(label, direction, code, position, entity, result)
      if CashMotif.exists?(label: label)
        result.kept << label
        return
      end

      account = GeneralAccount.find_by(code: code)
      if account.nil?
        result.missing_accounts << "#{code} (motif « #{label} » non créé)"
        return
      end

      CashMotif.create!(label: label, direction: direction, general_account: account,
                        legal_entity: entity, position: position)
      result.created << label
    end

    # « Caisse centrale » n'est créée que s'il n'existe AUCUNE caisse active.
    #
    # La production tient la sienne dans « Caisse du domaine » (1 285 lignes
    # reprises) : chercher un NOM en dur y a créé une seconde caisse, vide, que
    # la feuille de caisse aurait ensuite garnie pendant que l'argent réel
    # dormait dans l'autre. On cherche donc un compte de type `cash` actif —
    # décision 1, une seule caisse comptable.
    def ensure_cash_account!(entity)
      return false if CashAccount.actives.exists?(kind: "cash")
      return false if CashAccount.exists?(name: CASH_ACCOUNT_NAME)

      general = GeneralAccount.find_by(code: CASH_GENERAL_CODE)
      return false if general.nil?

      CashAccount.create!(name: CASH_ACCOUNT_NAME, kind: "cash",
                          general_account: general, legal_entity: entity)
      true
    end
  end
end
