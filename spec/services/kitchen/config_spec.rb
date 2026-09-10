require "rails_helper"

# Paramètres de l'offre de cuisine (epic #219, phase 2).
RSpec.describe Kitchen::Config do
  describe "défauts d'une installation neuve" do
    it "propose les trois familles" do
      expect(described_class.enabled?("repas")).to be(true)
      expect(described_class.enabled?("buffet")).to be(true)
      expect(described_class.enabled?("apero")).to be(true)
      # `trio` et `gouter` ne sont plus PROPOSABLES depuis l'issue #238 : le
      # premier est devenu le bouton « Trio » de la grille, le second se coche
      # dans la grille plutôt qu'il ne se choisit.
      expect(described_class.enabled_kinds).to eq(%w[repas buffet_vege buffet_viande apero])
    end

    it "porte les plafonds et délais d'usage" do
      expect(described_class.max_people("repas")).to eq(25)
      expect(described_class.max_people("buffet")).to be_nil
      expect(described_class.lead_days("repas")).to eq(7)
      expect(described_class.lead_days("apero")).to eq(5)
    end

    it "n'a aucun responsable par défaut et connaît l'email de coordination" do
      expect(described_class.default_human("repas")).to be_nil
      expect(described_class.coordinator_email).to eq("malau@les4sources.be")
    end
  end

  describe "après paramétrage" do
    it "retire une famille de l'offre sans toucher aux autres" do
      Setting.set("kitchen.apero.enabled", "0")

      expect(described_class.enabled?("apero")).to be(false)
      expect(described_class.enabled_kinds).to eq(%w[repas buffet_vege buffet_viande])
    end

    it "lit le responsable par défaut" do
      steph = Human.create!(name: "Stéphanie", email: "steph@les4sources.be")
      Setting.set("kitchen.repas.default_human_id", steph.id)

      expect(described_class.default_human("repas")).to eq(steph)
    end

    it "distingue un plafond effacé d'un plafond jamais posé" do
      Setting.set("kitchen.repas.max_people", "")
      expect(described_class.max_people("repas")).to be_nil

      Setting.set("kitchen.repas.max_people", "40")
      expect(described_class.max_people("repas")).to eq(40)
    end
  end

  # Les dépenses de la cuisine s'imputent en compta, sur des comptes dédiés
  # (epic #269, phase 1). C'est ce réglage que lira le reporting de période.
  describe "comptes de charge" do
    let!(:repas) { GeneralAccount.create!(code: "600005", name: "Achats cuisine — repas") }
    let!(:buffets) { GeneralAccount.create!(code: "600006", name: "Achats cuisine — buffets et apéros") }

    it "ne retourne aucun compte tant que rien n'est configuré" do
      expect(described_class.expense_accounts).to eq([])
      expect(described_class.expense_account_ids).to eq([])
    end

    it "retourne les comptes configurés, dans l'ordre du plan comptable" do
      Setting.set(described_class::EXPENSE_ACCOUNTS_KEY, "#{buffets.id},#{repas.id}")

      expect(described_class.expense_accounts).to eq([repas, buffets])
    end

    it "retourne un tableau vide sur un réglage vidé" do
      Setting.set(described_class::EXPENSE_ACCOUNTS_KEY, "")

      expect(described_class.expense_accounts).to eq([])
    end

    # On relit la base plutôt que de croire les identifiants stockés : un compte
    # supprimé depuis disparaît de la liste au lieu de faire planter la lecture.
    it "ignore un identifiant qui ne désigne plus rien" do
      Setting.set(described_class::EXPENSE_ACCOUNTS_KEY, "#{repas.id},999999,pas-un-id")

      expect(described_class.expense_accounts).to eq([repas])
    end

    it "ne propose au choix que les charges actives" do
      GeneralAccount.create!(code: "700200", name: "Repas")
      GeneralAccount.create!(code: "600007", name: "Compte retiré", active: false)

      expect(described_class.selectable_expense_accounts.to_a).to eq([repas, buffets])
    end
  end
end
