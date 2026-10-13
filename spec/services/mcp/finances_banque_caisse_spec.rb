require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Comptabilité > Banque & caisse dans le connecteur (Michael, 2026-10-13) : le
# dépôt d'un fichier CODA, le comptage et les motifs de caisse, Stripe et le
# coût d'encaissement — aperçu d'abord, accord ensuite.
RSpec.describe Mcp::Server, "finances : banque et caisse" do
  include FinanceBuilders

  let!(:entity) { build_legal_entity(name: "Fondation Les 4 Sources") }
  let!(:fiscal_year) { build_fiscal_year(entity, year: Date.current.year) }
  let!(:banque) { build_general_account(code: "550000", name: "Banque") }
  let!(:caisse_generale) { build_general_account(code: "570000", name: "Caisse") }
  let!(:bar) { build_general_account(code: "700300", name: "Bar et cellier", klass: 7, nature: "revenue") }
  let!(:ecarts) do
    build_general_account(code: GeneralAccount::CASH_DIFFERENCE_CODE, name: "Écarts de caisse", klass: 6, nature: "expense")
  end
  let!(:caisse) { build_cash_account(entity, caisse_generale, name: "Caisse du domaine", kind: "cash") }

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

  describe "un fichier CODA" do
    let!(:belfius) do
      CashAccount.create!(name: "Belfius", kind: "bank", legal_entity: entity, general_account: banque,
                          iban: "BE55068000000000")
    end
    let(:contenu) { Rails.root.join("spec/fixtures/coda/nominal.cod").read }

    it "montre ce que le dépôt créerait, l'importe à l'accord, puis refuse de le rejouer" do
      apercu = texte(outil("importer_coda", { "contenu" => contenu, "nom_fichier" => "belfius.cod" }))
      expect(apercu).to include("APERÇU", "2 ligne(s) créée(s)")
      expect(CashEntry.count).to eq(0)
      expect(CodaImport.count).to eq(0)

      expect(confirme("importer_coda", { "contenu" => contenu, "nom_fichier" => "belfius.cod" })).to include("À affecter")
      expect(CashEntry.where(cash_account: belfius).pending.count).to eq(2)
      depot = CodaImport.last
      expect(depot.whodunnit).to eq("claude:chloe@example.com")

      expect(texte(outil("imports_coda", {}))).to include("##{depot.id}", "belfius.cod", "2 ligne(s) créée(s)")
      expect(texte(outil("imports_coda", { "import" => depot.id }))).to include("Relevé n°001", "Belfius")

      deuxieme = outil("importer_coda", { "contenu" => contenu, "nom_fichier" => "encore.cod" })
      expect(deuxieme[:isError]).to be(true)
      expect(texte(deuxieme)).to include("déjà été déposé")
    end

    it "dit pourquoi un fichier est refusé, sans rien écrire" do
      resultat = outil("importer_coda", { "contenu" => "pas un fichier CODA", "nom_fichier" => "faux.cod" })

      expect(resultat[:isError]).to be(true)
      expect(texte(resultat)).to include("Fichier refusé")
      expect(CodaImport.count).to eq(0)
    end
  end

  describe "le comptage de caisse" do
    let!(:motif_bar) { CashMotif.create!(label: "Bar", direction: "in", general_account: bar, legal_entity: entity, position: 1) }

    before do
      Finance::RecordCashLine.new(cash_account: caisse, motif: motif_bar, entry_date: Date.current,
                                  label: "Recette du bar", amount_cents: 13_000).run!
    end

    it "valide une caisse juste" do
      resultat = confirme("compter_caisse", { "grille" => { "50" => 2, "20" => "1", "10" => 1 } })

      expect(resultat).to include("caisse juste au centime")
      expect(CashCount.last).to have_attributes(status: "validated", counted_cents: 13_000, counted_by: user)
      expect(texte(outil("comptages_caisse", {}))).to include("130,00 € attendus", "juste · validé")
    end

    it "exige une issue pour un écart, garde un brouillon, puis assume l'écart à la reprise" do
      sans_issue = outil("compter_caisse", { "grille" => { "50" => 2 } })
      expect(sans_issue[:isError]).to be(true)
      expect(texte(sans_issue)).to include("ne tombe pas juste")

      brouillon = confirme("compter_caisse", { "grille" => { "50" => 2 }, "issue" => "retrouver",
                                               "commentaire" => "un ticket de 30 € à retrouver" })
      expect(brouillon).to include("BROUILLON")
      comptage = CashCount.last
      expect(comptage).to be_draft
      expect(CashEntry.where(cash_account: caisse).count).to eq(1)

      confirme("compter_caisse", { "comptage" => comptage.id, "grille" => { "50" => 2 }, "issue" => "assumer",
                                   "commentaire" => "introuvable" })
      expect(comptage.reload).to be_validated
      expect(comptage.adjustment_cash_entry.amount_cents).to eq(-3_000)

      refus = outil("compter_caisse", { "comptage" => comptage.id, "grille" => { "50" => 2 } })
      expect(texte(refus)).to include("validé : il ne se modifie plus")
    end

    it "refuse une coupure qui n'existe pas" do
      expect(texte(outil("compter_caisse", { "grille" => { "3" => 1 } }))).to include("Coupure inconnue")
    end
  end

  describe "les motifs de caisse" do
    let!(:depot) { CashMotif.create!(label: "Dépôt banque", direction: "out", general_account: banque, legal_entity: entity, position: 1) }

    it "crée un motif, le remonte, le désactive puis le réactive" do
      resultat = confirme("motif_caisse", { "geste" => "creer", "libelle" => "Vente bar", "sens" => "entree", "compte" => "700300" })
      expect(resultat).to include("« Vente bar »", "entrée", "700300")
      vente = CashMotif.find_by(label: "Vente bar")
      expect(vente).to have_attributes(legal_entity: entity, position: 2)

      confirme("motif_caisse", { "geste" => "monter", "motif_caisse" => "Vente bar" })
      expect(CashMotif.ordered.first).to eq(vente)
      expect(texte(outil("motif_caisse", { "geste" => "monter", "motif_caisse" => "Vente bar" }))).to include("déjà en tête")

      confirme("motif_caisse", { "geste" => "desactiver", "motif_caisse" => vente.id })
      expect(vente.reload.active).to be(false)
      expect(texte(outil("referentiel_comptable", { "quoi" => "motifs_caisse" }))).to include("Vente bar", "DÉSACTIVÉ")

      confirme("motif_caisse", { "geste" => "reactiver", "motif_caisse" => "vente bar" })
      expect(vente.reload.active).to be(true)
    end
  end

  describe "Stripe" do
    let!(:stripe_general) { build_general_account(code: "551000", name: "Stripe") }
    let!(:ventes) { build_general_account(code: "700100", name: "Ventes épicerie", klass: 7, nature: "revenue") }
    let!(:compte) do
      CashAccount.create!(name: "Stripe Tranches de Vie", kind: "stripe", legal_entity: entity, general_account: stripe_general,
                          stripe_account_key: "tranche_de_vie", stripe_mode: "per_payout")
    end

    it "passe un compte en grand livre, y fait correspondre une catégorie et refuse le retour en arrière" do
      confirme("mode_stripe", { "compte" => "Tranches de Vie", "mode" => "grand_livre" })
      expect(compte.reload.stripe_mode).to eq("ledger")

      StripeBalanceTransaction.create!(account_key: "tranche_de_vie", cash_account: compte, stripe_id: "txn_1", kind: "charge",
                                       category: "pain", gross_cents: 1_000, fee_cents: 30, net_cents: 970, occurred_at: Time.current)
      expect(texte(outil("comptes_stripe", {}))).to include("Grand livre", "Catégories sans correspondance", "pain : 1 transaction")

      confirme("correspondance_stripe", { "geste" => "creer", "compte" => "Tranches de Vie", "categorie" => "pain",
                                          "compte_general" => "700100" })
      correspondance = StripeCategoryMapping.last
      expect(correspondance).to have_attributes(account_key: "tranche_de_vie", category: "pain", general_account: ventes)
      expect(texte(outil("comptes_stripe", {}))).to include("##{correspondance.id} pain → 700100")

      retour = outil("mode_stripe", { "compte" => "Tranches de Vie", "mode" => "par_versement" })
      expect(texte(retour)).to include("Refusé")

      confirme("correspondance_stripe", { "geste" => "retirer", "correspondance" => correspondance.id })
      expect(StripeCategoryMapping.count).to eq(0)
    end

    it "déclare le justificatif d'un mois et montre l'écart dans le coût d'encaissement" do
      mois = Date.current.strftime("%Y-%m")
      confirme("justificatif_stripe", { "compte" => "Tranche de Vie", "mois" => mois, "montant" => "12,34", "reference" => "INV-42" })
      expect(StripeFeeInvoice.last).to have_attributes(account_key: "tranche_de_vie", declared_fee_cents: 1_234)

      cout = texte(outil("cout_encaissement", {}))
      expect(cout).to include("Justificatifs mensuels", "déclaré 12,34 €", "ÉCART +12,34 €", "réf. INV-42")

      confirme("justificatif_stripe", { "geste" => "retirer", "compte" => "tranche_de_vie", "mois" => mois })
      expect(StripeFeeInvoice.count).to eq(0)
    end
  end
end
