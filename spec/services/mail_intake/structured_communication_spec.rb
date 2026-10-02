require "rails_helper"

RSpec.describe MailIntake::StructuredCommunication do
  it "accepte une communication dont la clé modulo 97 est juste, sous toutes ses écritures" do
    %w[+++000/0024/11862+++ ***000/0024/11862*** 000002411862].each do |ecrite|
      expect(described_class.normalize(ecrite)).to eq("+++000/0024/11862+++")
    end
    expect(described_class.normalize("+++ 508 / 9770 / 02287 +++")).to eq("+++508/9770/02287+++")
  end

  it "refuse une clé fausse, et ce qui n'est pas une communication" do
    expect(described_class.normalize("+++090/1234/56789+++")).to be_nil
    expect(described_class.normalize("Facture 2026-093")).to be_nil
    expect(described_class.normalize("12345")).to be_nil
  end

  it "prend 97 comme clé quand le reste est nul" do
    expect(described_class.normalize("+++000/0000/00097+++")).to eq("+++000/0000/00097+++")
  end

  it "trouve dans un texte les seules communications valides" do
    texte = "Communication : +++000/1223/35386+++ (et non +++090/1234/56789+++), rappel ***000/1223/35386***"
    expect(described_class.scan(texte)).to eq(["+++000/1223/35386+++"])
  end
end
