# Epic #359, phase 1, décisions 14 et 18 — les comptes de produit des trois
# carnets, et le motif de caisse « Épicerie » remis sur le bon compte.
#
# L'artisanat en dépôt-vente n'avait pas de compte de produit : il tombait dans
# le fourre-tout `700300 Bar et cellier`, où plus personne ne pouvait dire ce que
# l'armoire des artisans rapporte. `701005` le sépare. Le motif de caisse
# « Épicerie » pointait lui aussi sur `700300` ; il rejoint `701002 Cellier`.
#
# Idempotente et non destructive : les comptes déjà là ne sont pas renommés, et
# les affectations passées ne sont PAS réécrites — reclasser deux ans d'écritures
# derrière le dos du comptable serait une décision comptable, pas une migration.
class SeedShopRevenueAccounts < ActiveRecord::Migration[8.1]
  # Modèles locaux : la migration doit rester vraie même quand les modèles de
  # l'application auront changé.
  class Account < ActiveRecord::Base
    self.table_name = "general_accounts"
  end

  class Motif < ActiveRecord::Base
    self.table_name = "cash_motifs"
  end

  ACCOUNTS = [
    ["701002", "Cellier"],
    ["701003", "Boulangerie"],
    ["701005", "Artisanat (dépôt-vente)"]
  ].freeze

  def up
    ACCOUNTS.each do |code, name|
      next if Account.where(code: code).exists?

      Account.create!(code: code, name: name, klass: 7, nature: "revenue",
                      reconcilable: false, active: true,
                      created_at: Time.current, updated_at: Time.current)
    end

    grocery = Account.find_by(code: "701002")
    return if grocery.nil?

    Motif.where(label: "Épicerie").update_all(general_account_id: grocery.id, updated_at: Time.current)
  end

  # Irréversible côté données : on ne sait pas si `701005` est resté vide, ni sur
  # quel compte « Épicerie » pointait avant. Rien à défaire non plus — les
  # comptes créés ne gênent personne.
  def down; end
end
