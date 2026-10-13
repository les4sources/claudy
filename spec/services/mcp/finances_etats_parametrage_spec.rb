require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Comptabilité > États, échéancier et paramétrage dans le connecteur
# (Michael, 2026-10-13) : lire le grand livre et les balances, tenir
# l'échéancier, régler le plan comptable, les entités et les exercices.
RSpec.describe Mcp::Server, "finances : états et paramétrage" do
  include FinanceBuilders

  let(:annee) { Date.current.year }
  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: annee) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque", klass: 5, nature: "asset") }
  let!(:ventes) { build_general_account(code: "700000", name: "Ventes", klass: 7, nature: "revenue") }
  let!(:loyer) { build_general_account(code: "610000", name: "Loyers", klass: 6, nature: "expense") }

  let(:user) { User.create!(email: "chloe@example.com", password: "secret123456") }
  let(:server) { described_class.new(user: user) }

  def outil(name, arguments)
    server.handle({ "jsonrpc" => "2.0", "id" => 1, "method" => "tools/call",
                    "params" => { "name" => name, "arguments" => arguments } })[:result]
  end

  def texte(result) = result[:content].first[:text]

  def confirme(name, arguments)
    apercu = outil(name, arguments)
    expect(apercu[:isError]).to be(false), texte(apercu)
    resultat = outil(name, arguments.merge("confirmation" => texte(apercu)[/confirmation: "([^"]+)"/, 1]))
    expect(resultat[:isError]).to be(false), texte(resultat)
    texte(resultat)
  end

  describe "les états" do
    before do
      post_simple_entry(entity: entity, debit_account: banque, credit_account: ventes, amount_cents: 50_000,
                        entry_date: Date.new(annee, 2, 10), label: "Séjour Dupont")
      post_simple_entry(entity: entity, debit_account: loyer, credit_account: banque, amount_cents: 20_000,
                        entry_date: Date.new(annee, 3, 1), label: "Loyer mars")
    end

    it "lit le grand livre, la balance et la balance analytique" do
      livre = texte(outil("grand_livre", { "compte" => "550000" }))
      expect(livre).to include("Séjour Dupont", "débit 500,00 €", "crédit 200,00 €", "Solde de clôture : 300,00 € débiteur")

      ouverture = texte(outil("grand_livre", { "compte" => "550000", "du" => "#{annee}-02-15" }))
      expect(ouverture).to include("Solde d'ouverture : 500,00 € débiteur")

      balance = texte(outil("balance_comptable", {}))
      expect(balance).to include("700000 Ventes", "solde 500,00 € créditeur", "équilibrée")

      analytique = texte(outil("balance_comptable", { "vue" => "analytique" }))
      expect(analytique).to include("Non ventilé", "charges 200,00 €", "produits 500,00 €", "résultat 300,00 €")

      croise = texte(outil("controle_croise", { "mois" => "#{annee}-02" }))
      expect(croise).to include("Produits au journal : 500,00 €")

      expect(texte(outil("vue_comptabilite", {}))).to include("Fondation Les 4 Sources", "exercice(s) ouvert(s) : #{annee}")
    end
  end

  describe "l'échéancier" do
    it "crée une obligation, ses échéances, puis fait et rouvre une échéance" do
      confirme("obligation", { "titre" => "Déclaration TVA", "entite" => "Fondation", "frequence" => "trimestrielle",
                               "premiere_echeance" => (Date.current + 20).to_s, "consignes" => "Intervat" })
      obligation = ComplianceObligation.last
      expect(obligation).to have_attributes(frequency: "quarterly", covers: "previous", responsible_user: user)
      expect(obligation.compliance_deadlines.count).to be >= 4

      liste = texte(outil("echeancier", {}))
      expect(liste).to include("À 30 jours (1)", "Déclaration TVA")
      echeance = obligation.compliance_deadlines.order(:due_on).first
      expect(texte(outil("echeancier", { "echeance" => echeance.id }))).to include("Consignes : Intervat")

      confirme("echeance", { "geste" => "modifier", "echeance" => echeance.id, "note" => "Chiffres chez Seb" })
      expect(echeance.reload.note).to eq("Chiffres chez Seb")
      confirme("echeance", { "geste" => "faire", "echeance" => echeance.id })
      expect(echeance.reload).to have_attributes(status: "done", done_by_user: user)
      confirme("echeance", { "geste" => "rouvrir", "echeance" => echeance.id })
      expect(echeance.reload.status).to eq("todo")

      confirme("obligation", { "obligation" => obligation.id, "active" => false })
      expect(obligation.reload).not_to be_active
      expect(texte(outil("echeancier", { "obligations" => true }))).to include("Déclaration TVA", "INACTIVE")
    end
  end

  describe "le paramétrage" do
    it "crée, corrige et supprime un compte ; refuse de supprimer un compte mouvementé" do
      confirme("compte_general", { "code" => "613500", "nom" => "Honoraires" })
      compte = GeneralAccount.find_by(code: "613500")
      expect(compte).to have_attributes(klass: 6, nature: "expense")

      confirme("compte_general", { "compte" => "613500", "lettrable" => true })
      expect(compte.reload.reconcilable).to be(true)
      expect(texte(outil("parametrage_compta", { "quoi" => "comptes", "classe" => 6 }))).to include("613500 Honoraires", "lettrable")

      confirme("compte_general", { "compte" => "613500", "supprimer" => true })
      expect(GeneralAccount.find_by(code: "613500")).to be_nil

      post_simple_entry(entity: entity, debit_account: banque, credit_account: ventes, entry_date: Date.new(annee, 2, 10))
      expect(texte(outil("compte_general", { "compte" => "700000", "supprimer" => true }))).to include("désactive-le")
    end

    it "crée une entité et son exercice, puis clôture l'exercice" do
      confirme("entite_juridique", { "nom" => "SRL Les 4 Sources", "forme" => "srl", "tva" => "assujettie", "numero_tva" => "BE0123456789" })
      srl = LegalEntity.find_by(name: "SRL Les 4 Sources")
      expect(srl).to have_attributes(form: "srl", vat_regime: "subject")

      confirme("exercice", { "entite" => "SRL", "debut" => "#{annee}-01-01" })
      exercice = FiscalYear.find_by(legal_entity: srl)
      expect(exercice.ends_on).to eq(Date.new(annee, 12, 31))

      expect(texte(outil("entite_juridique", { "entite" => "SRL", "supprimer" => true }))).to include("1 exercice(s)")

      cloture = { "exercice" => annee.to_s, "entite" => "SRL", "cloturer" => true }
      expect(texte(outil("exercice", cloture))).to include("IRRÉVERSIBLE")
      confirme("exercice", cloture)
      expect(exercice.reload).to be_closed
      expect(texte(outil("parametrage_compta", { "quoi" => "exercices", "entite" => "SRL" }))).to include("clôturé")
    end
  end
end
