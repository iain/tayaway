# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe GeoIP do
  let(:tmpdir) { Dir.mktmpdir }
  let(:mmdb_path) { File.join(tmpdir, "test.mmdb") }

  before do
    stub_const("GeoIP::MMDB_PATH", mmdb_path)
    described_class.instance_variables.each { |v| described_class.remove_instance_variable(v) }
  end

  after { FileUtils.remove_entry(tmpdir) }

  describe ".lookup" do
    it "returns nil when no mmdb file is present" do
      expect(described_class.lookup("8.8.8.8")).to be_nil
    end

    it "rebuilds the handle when the file mtime changes (zero-restart refresh)" do
      v1 = instance_double(MaxMindDB, lookup: { city: "Amsterdam", country: "Netherlands" })
      v2 = instance_double(MaxMindDB, lookup: { city: "Berlin", country: "Germany" })

      File.write(mmdb_path, "v1")
      File.utime(Time.now - 60, Time.now - 60, mmdb_path)
      allow(MaxMindDB).to receive(:new).with(mmdb_path).and_return(v1)
      expect(described_class.lookup("8.8.8.8")).to eq(city: "Amsterdam", country: "Netherlands")

      File.write(mmdb_path, "v2")
      File.utime(Time.now, Time.now, mmdb_path)
      allow(MaxMindDB).to receive(:new).with(mmdb_path).and_return(v2)
      expect(described_class.lookup("8.8.8.8")).to eq(city: "Berlin", country: "Germany")
    end

    it "does not rebuild the handle when mtime is unchanged" do
      File.write(mmdb_path, "v1")
      v1 = instance_double(MaxMindDB, lookup: { city: "Amsterdam", country: "Netherlands" })
      allow(MaxMindDB).to receive(:new).with(mmdb_path).and_return(v1)

      3.times { described_class.lookup("8.8.8.8") }

      expect(MaxMindDB).to have_received(:new).once
    end

    it "drops the cached handle when the file disappears" do
      File.write(mmdb_path, "v1")
      v1 = instance_double(MaxMindDB, lookup: { city: "Amsterdam", country: "Netherlands" })
      allow(MaxMindDB).to receive(:new).with(mmdb_path).and_return(v1)

      expect(described_class.lookup("8.8.8.8")).to eq(city: "Amsterdam", country: "Netherlands")

      File.delete(mmdb_path)
      expect(described_class.lookup("8.8.8.8")).to be_nil
    end
  end
end
