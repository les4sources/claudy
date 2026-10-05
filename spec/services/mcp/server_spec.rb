require "rails_helper"

# Le protocole MCP et les outils de comptes (Michael, 2026-10-05) : ce que
# Claude peut lire et, surtout, ce qu'il ne peut PAS écrire sans aperçu.
RSpec.describe Mcp::Server do
  let(:user) { User.create!(email: "michael@example.com", password: "secret123456") }
  let(:server) { described_class.new(user: user) }
  let(:household) { Household.create!(name: "Frennet") }
  let(:compte) { MemberAccount.create!(kind: "household", household: household, name: "Seb & Mag") }
  let!(:poulets) do
    compte.account_entries.create!(entry_date: Date.new(2025, 11, 26), amount_cents: 9_217, flow: "grocery",
                                   kind: "grocery", label: "Vente de poulets")
  end
  let!(:bar_2025) do
    compte.account_entries.create!(entry_date: Date.new(2025, 6, 30), amount_cents: 5_000, flow: "bar", kind: "bar",
                                   label: "Bar juin 2025")
  end

  def rpc(method, params = {}, id: 1)
    server.handle({ "jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params })
  end

  def outil(name, arguments)
    rpc("tools/call", { "name" => name, "arguments" => arguments })[:result]
  end

  def texte(result) = result[:content].first[:text]
  def code_de(result) = texte(result)[/confirmation: "([^"]+)"/, 1]

  describe "protocole" do
    it "négocie la version demandée quand il la connaît" do
      expect(rpc("initialize", { "protocolVersion" => "2025-06-18" })[:result][:protocolVersion]).to eq("2025-06-18")
      expect(rpc("initialize", { "protocolVersion" => "1999-01-01" })[:result][:protocolVersion])
        .to eq(described_class::PROTOCOL_VERSIONS.first)
    end

    it "ne répond rien à une notification" do
      expect(server.handle({ "jsonrpc" => "2.0", "method" => "notifications/initialized" })).to be_nil
    end

    it "liste les outils, ceux qui écrivent marqués comme tels" do
      outils = rpc("tools/list")[:result][:tools].index_by { |t| t[:name] }
      expect(outils.keys).to include("diagnostic_compte", "supprimer_lignes", "encoder_reglement")
      expect(outils["diagnostic_compte"][:annotations]).to include(readOnlyHint: true, destructiveHint: false)
      expect(outils["supprimer_lignes"][:annotations]).to include(readOnlyHint: false, destructiveHint: true)
      expect(outils["supprimer_lignes"][:inputSchema][:properties]).to include(:confirmation, :motif)
    end

    it "refuse une méthode inconnue" do
      expect(rpc("resources/list")[:error][:code]).to eq(-32_601)
    end
  end

  describe "lecture" do
    it "diagnostique un compte retrouvé par le nom de son ménage" do
      result = outil("diagnostic_compte", { "compte" => "frennet" })
      expect(result[:isError]).to be(false)
      expect(texte(result)).to include(compte.code, "Épicerie : 92,17 €", "Bar : 50,00 €")
    end

    it "rend une erreur lisible pour un compte inconnu" do
      result = outil("lignes_compte", { "compte" => "personne" })
      expect(result[:isError]).to be(true)
      expect(texte(result)).to include("Aucun compte")
    end
  end

  describe "écriture" do
    let(:arguments) { { "compte" => compte.code, "lignes" => [poulets.id], "motif" => "double facturation" } }

    it "n'écrit rien sans confirmation et montre l'effet" do
      result = outil("supprimer_lignes", arguments)
      expect(texte(result)).to include("APERÇU", "Après : Bar 50,00 €")
      expect(AccountEntry.exists?(poulets.id)).to be(true)
    end

    it "applique ce qui a été vu, signé du compte et du motif" do
      code = code_de(outil("supprimer_lignes", arguments))
      result = outil("supprimer_lignes", arguments.merge("confirmation" => code))

      expect(result[:isError]).to be(false)
      expect(AccountEntry.exists?(poulets.id)).to be(false)
      expect(PaperTrail::Version.where(item_type: "AccountEntry", item_id: poulets.id).last.whodunnit)
        .to eq("claude:michael@example.com — double facturation")
    end

    it "refuse un code dont le plan a changé" do
      code = code_de(outil("supprimer_lignes", arguments))
      result = outil("supprimer_lignes", arguments.merge("lignes" => [poulets.id, bar_2025.id], "confirmation" => code))

      expect(result[:isError]).to be(true)
      expect(AccountEntry.where(id: [poulets.id, bar_2025.id]).count).to eq(2)
    end

    it "refuse un code forgé" do
      result = outil("supprimer_lignes", arguments.merge("confirmation" => "n'importe-quoi"))
      expect(result[:isError]).to be(true)
      expect(texte(result)).to include("invalide ou expiré")
    end

    it "renvoie une ligne verrouillée vers la contre-écriture" do
      poulets.update!(locked_at: Time.current)
      result = outil("supprimer_lignes", arguments)
      expect(result[:isError]).to be(true)
      expect(texte(result)).to include("contre_passer_lignes")
    end

    it "abandonne la dette ancienne d'un poste, une seule fois" do
      abandon = { "poste" => "bar", "jusqu_au" => "2025-12-31", "motif" => "comptes clôturés" }
      outil("abandonner_dette", abandon.merge("confirmation" => code_de(outil("abandonner_dette", abandon))))

      expect(MemberAccounts::Outstanding.new(compte.reload).poste("bar")).to be_nil
      expect(outil("abandonner_dette", abandon)[:isError]).to be(true)
    end

    it "encode un règlement qui paie le mois qu'il nomme" do
      reglement = { "compte" => compte.code, "montant" => "50", "recu_le" => "2026-01-10", "poste" => "bar",
                    "reference" => "reprise-bar:2025-06" }
      outil("encoder_reglement", reglement.merge("confirmation" => code_de(outil("encoder_reglement", reglement))))

      expect(compte.account_settlements.sole.reference).to eq("reprise-bar:2025-06")
      expect(MemberAccounts::Outstanding.new(compte.reload).poste("bar")).to be_nil
      expect(outil("encoder_reglement", reglement)[:isError]).to be(true)
    end
  end
end
