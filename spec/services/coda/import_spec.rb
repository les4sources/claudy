require "rails_helper"
require Rails.root.join("spec/support/finance_builders")

# Ce qui compte ici n'est pas qu'un import réussisse — c'est qu'un import qui
# ne devrait pas passer ne laisse RIEN derrière lui, et qu'un fichier redéposé
# ne double rien.
RSpec.describe Coda::Import do
  include FinanceBuilders

  let(:entity) { build_legal_entity }
  let!(:fiscal_year) { build_fiscal_year(entity) }
  let(:bank_account) { build_general_account(code: "550000", name: "Banque") }
  let!(:cash_account) do
    CashAccount.create!(name: "Triodos", kind: "bank", legal_entity: entity,
                        general_account: bank_account, iban: "BE55068000000000")
  end

  def fixture(name) = Rails.root.join("spec/fixtures/coda/#{name}.cod").read
  def import(name) = described_class.new(content: fixture(name), filename: "#{name}.cod").run!

  describe "un fichier nominal" do
    it "crée une ligne de trésorerie par mouvement, en attente d'affectation" do
      expect { import("nominal") }.to change { CashEntry.count }.by(2)

      entries = CashEntry.order(:entry_date)
      expect(entries.map(&:amount_cents)).to eq([130_000, -45_000])
      expect(entries.map(&:status).uniq).to eq(["pending"])
      expect(entries.first.communication).to include("VIREMENT GROUPE DUPONT")
    end

    it "n'invente aucune affectation" do
      import("nominal")

      expect(CashAllocation.count).to eq(0)
    end

    it "garde le fichier et son relevé" do
      report = import("nominal")

      expect(report.status).to eq("imported")
      expect(CodaImport.last.status).to eq("imported")
      expect(CodaStatement.last.sequence_number).to eq("001")
      expect(CodaStatement.last.new_balance_cents).to eq(185_000)
    end
  end

  describe "l'idempotence" do
    it "refuse de rejouer le même fichier — niveau sha256" do
      import("nominal")

      expect { @report = import("nominal") }.not_to change { CashEntry.count }
      expect(@report.status).to eq("already_imported")
    end

    # Le cas courant : les banques renvoient volontiers des fichiers qui se
    # chevauchent. C'est le MOUVEMENT, et non le relevé, qui doit être idempotent
    # — un relevé peut arriver deux fois en portant la seconde fois des lignes
    # nouvelles, et c'est même la règle chez Triodos.
    it "ignore les mouvements déjà importés arrivés dans un autre fichier" do
      import("nominal")
      autre = fixture("nominal").sub("TESTFILE01", "TESTFILE02")

      report = described_class.new(content: autre, filename: "bis.cod").run!

      expect(report.entries_created).to eq(0)
      expect(report.entries_skipped).to eq(2)
      expect(CashEntry.count).to eq(2)
    end

    # Le piège dans lequel le premier export Triodos est tombé : refusé pour un
    # doublon qui n'en était pas un, il devenait ensuite impossible à redéposer
    # une fois le refus corrigé. Un dépôt sans effet doit rester rejouable.
    it "reprend un dépôt antérieur qui n'avait créé aucune ligne" do
      import("nominal")
      sterile = fixture("nominal").sub("TESTFILE01", "TESTFILE02")
      described_class.new(content: sterile, filename: "sterile.cod").run!
      expect(CodaImport.count).to eq(2)

      report = described_class.new(content: sterile, filename: "sterile.cod").run!

      expect(report.status).to eq("imported")
      expect(CodaImport.count).to eq(2)
      expect(report.to_text).to include("repris")
    end

    it "refuse le redépôt d'un fichier qui, lui, avait créé des lignes" do
      import("nominal")

      report = import("nominal")

      expect(report.status).to eq("already_imported")
      expect(CashEntry.count).to eq(2)
    end
  end

  # Triodos n'expose pas de relevés numérotés : chaque export « mutations » porte
  # le relevé 000 et renumérote ses mouvements à partir de 1. Deux exports
  # successifs sont donc indiscernables pour qui regarde le numéro de relevé —
  # et c'est exactement ce que l'import regardait.
  describe "les exports qui se recouvrent" do
    it "n'importe que la part nouvelle du second export" do
      premier = import("triodos_1")
      expect(premier.entries_created).to eq(3)

      second = import("triodos_2")

      expect(second.entries_created).to eq(2)
      expect(second.entries_skipped).to eq(3)
      expect(CashEntry.count).to eq(5)
      expect(CashEntry.sum(:amount_cents)).to eq(32_950)
    end

    it "garde le second relevé 000 malgré le numéro déjà vu" do
      import("triodos_1")
      import("triodos_2")

      expect(CodaStatement.count).to eq(2)
      expect(CodaStatement.pluck(:sequence_number)).to eq(%w[000 000])
      expect(CodaStatement.last_for(cash_account).new_balance_cents).to eq(132_950)
    end

    # Le reproche exact de l'ancien import : il refusait tout ce qui n'était pas
    # bout à bout, alors qu'aucune période ne manquait.
    it "accepte un ancien solde antérieur au dernier relevé importé" do
      import("triodos_1")

      expect { import("triodos_2") }.not_to raise_error
    end

    it "refuse un fichier dont la zone commune ne décrit plus les mêmes mouvements" do
      import("triodos_1")

      expect {
        expect { import("recouvrement_altere") }.to raise_error(described_class::Rejected, /doublon/)
      }.not_to change { CashEntry.count }
    end
  end

  # Deux mouvements peuvent être identiques en tout point : même jour, même
  # montant, même communication. Les confondre perdrait un encaissement réel.
  describe "les mouvements identiques du même jour" do
    it "les garde tous les deux" do
      report = import("doublons_jour")

      expect(report.entries_created).to eq(2)
      expect(CashEntry.sum(:amount_cents)).to eq(11_000)
    end

    # Un export pris en cours de journée arrête le solde au milieu des mouvements
    # du jour. Le lendemain, la même date en porte un autre — sans que rien soit
    # faux. C'est pourquoi la continuité ne reconstitue aucun solde.
    it "ajoute le troisième tombé après le premier export, sans rejouer les deux autres" do
      import("doublons_jour")

      report = import("doublons_jour_suite")

      expect(report.entries_created).to eq(1)
      expect(report.entries_skipped).to eq(2)
      expect(CashEntry.count).to eq(3)
    end
  end

  describe "les contrôles bloquants" do
    it "refuse un relevé qui ne se referme pas sur lui-même, sans rien créer" do
      expect {
        expect { import("ecart_intra") }.to raise_error(described_class::Rejected, /ne correspond pas/)
      }.not_to change { CashEntry.count }

      expect(CodaImport.count).to eq(0)
    end

    it "refuse une rupture de chaînage entre deux relevés du fichier" do
      expect {
        expect { import("rupture_chainage") }.to raise_error(described_class::Rejected, /manque/)
      }.not_to change { CashEntry.count }
    end

    # Le trou entre deux imports : celui qu'aucun contrôle intra-fichier ne voit.
    it "refuse un fichier dont l'ancien solde ne suit pas le dernier relevé importé" do
      import("nominal")

      expect { import("trou_continuite") }.to raise_error(described_class::Rejected, /manque/)
      expect(CashEntry.count).to eq(2)
    end

    # Un débit et un crédit fabriqués qui se compensent satisfont les trois
    # autres contrôles : seul le total du fichier les attrape.
    it "refuse un fichier dont les totaux de fin ne collent pas aux mouvements lus" do
      lignes = fixture("nominal").lines
      index = lignes.index { |l| l.start_with?("9") }
      fin = lignes[index].dup
      fin[22, 15] = "000000099999000"
      lignes[index] = fin

      expect {
        expect {
          described_class.new(content: lignes.join, filename: "faux_total.cod").run!
        }.to raise_error(described_class::Rejected, /Total des débits/)
      }.not_to change { CashEntry.count }
    end

    it "refuse un IBAN qu'aucun compte de trésorerie ne porte" do
      cash_account.update!(iban: "BE99999999999999")

      expect {
        import("nominal")
      }.to raise_error(described_class::Rejected, /compte_tresorerie/)
    end
  end

  describe "plusieurs comptes" do
    let!(:second_account) do
      CashAccount.create!(name: "Triodos épargne", kind: "bank", legal_entity: entity,
                          general_account: bank_account, iban: "BE77068011111111")
    end

    it "répartit les lignes sur le bon compte" do
      import("multi_releves")

      expect(cash_account.cash_entries.count).to eq(1)
      expect(second_account.cash_entries.count).to eq(1)
      expect(second_account.cash_entries.first.amount_cents).to eq(-7_550)
    end

    # L'export Triodos du compte à vue ET de l'épargne : un fichier CODA complet
    # par compte et par période, mis bout à bout. L'ancien import le refusait en
    # bloc (« il suit l'enregistrement de fin »).
    describe "un export qui concatène plusieurs fichiers" do
      it "importe chaque relevé sur le compte de son IBAN" do
        report = import("triodos_multi_comptes")

        expect(report.status).to eq("imported")
        expect(report.statements).to eq(4)
        expect(report.entries_created).to eq(6)
        expect(cash_account.cash_entries.order(:entry_date, :amount_cents).pluck(:amount_cents))
          .to eq([13_000, -4_500, 7_550, 2_000])
        expect(second_account.cash_entries.order(:entry_date).pluck(:amount_cents)).to eq([-7_550, 5_000])
      end

      it "garde un relevé par fichier, numéroté sans heurter l'unicité, et retient le dernier" do
        import("triodos_multi_comptes")

        expect(CodaImport.count).to eq(1)
        expect(CodaStatement.where(cash_account: cash_account).order(:id).pluck(:sequence_number))
          .to eq(%w[000 000-02])
        expect(CodaStatement.last_for(cash_account).new_balance_cents).to eq(118_050)
        expect(CodaStatement.last_for(second_account).new_balance_cents).to eq(27_450)
      end

      # Un export plus ancien d'un seul compte est déjà là : le dépôt
      # multi-comptes le recouvre et n'en rejoue rien.
      it "se raccorde par recouvrement à ce qui est déjà importé" do
        import("triodos_1")

        report = import("triodos_multi_comptes")

        expect(report.entries_skipped).to eq(3)
        expect(report.entries_created).to eq(3)
        expect(cash_account.cash_entries.count).to eq(4)
        expect(cash_account.cash_entries.sum(:amount_cents)).to eq(18_050)
      end

      it "vérifie les totaux de chaque fichier, et dit lequel ne colle pas" do
        lignes = fixture("triodos_multi_comptes").lines
        fins = lignes.each_index.select { |i| lignes[i].start_with?("9") }
        fin = lignes[fins[1]].dup
        fin[22, 15] = "000000000099000"
        lignes[fins[1]] = fin

        expect {
          expect {
            described_class.new(content: lignes.join, filename: "altere.cod").run!
          }.to raise_error(described_class::Rejected, /fichier n°2 \(sur 4/)
        }.not_to change { CashEntry.count }
      end

      it "refuse un fichier dont le chaînage casse d'un relevé à l'autre du même compte" do
        lignes = fixture("triodos_multi_comptes").lines
        # Le troisième relevé (compte à vue, du 05/08) repart de 10 000 € au
        # lieu de 1 085 € : il se referme sur lui-même, mais ne suit pas le
        # premier.
        ouverture = lignes.each_index.select { |i| lignes[i].start_with?("1") }[2]
        cloture = lignes.each_index.select { |i| lignes[i].start_with?("8") }[2]
        lignes[ouverture] = lignes[ouverture].dup.tap { |l| l[43, 15] = "000000010000000" }
        lignes[cloture] = lignes[cloture].dup.tap { |l| l[42, 15] = "000000010095500" }

        expect {
          described_class.new(content: lignes.join, filename: "rupture.cod").run!
        }.to raise_error(described_class::Rejected, /ne suit pas/)
        expect(CashEntry.count).to eq(0)
      end
    end
  end
end
