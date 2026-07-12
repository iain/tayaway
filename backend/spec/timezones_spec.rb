# frozen_string_literal: true

require "spec_helper"

RSpec.describe Timezones do
  describe ".valid?" do
    it "accepts a known IANA identifier" do
      expect(described_class.valid?("Europe/Amsterdam")).to be(true)
    end

    it "rejects an unknown or blank identifier" do
      expect(described_class.valid?("Mars/Olympus_Mons")).to be(false)
      expect(described_class.valid?("")).to be(false)
      expect(described_class.valid?(nil)).to be(false)
    end
  end

  describe ".blank_or_valid?" do
    it "treats blank as valid (use the default / no change)" do
      expect(described_class.blank_or_valid?(nil)).to be(true)
      expect(described_class.blank_or_valid?("")).to be(true)
      expect(described_class.blank_or_valid?("   ")).to be(true)
    end

    it "accepts a known identifier, even with surrounding whitespace" do
      expect(described_class.blank_or_valid?("Europe/Amsterdam")).to be(true)
      expect(described_class.blank_or_valid?("  Europe/Amsterdam  ")).to be(true)
    end

    it "rejects an unknown identifier" do
      expect(described_class.blank_or_valid?("Mars/Olympus_Mons")).to be(false)
    end
  end

  describe ".today" do
    it "reads the current civil date in the given zone" do
      # Etc/GMT-12 (UTC+12) runs a full day ahead of Etc/GMT+12 (UTC-12) at
      # every instant, so their civil dates always differ by exactly one day —
      # a clock-independent way to show the date is read in the asked-for zone.
      expect(described_class.today("Etc/GMT-12") - described_class.today("Etc/GMT+12")).to eq(1)
    end
  end

  describe ".resolve" do
    def resolve(date, hour, min, zone)
      described_class.resolve(date: date, hour: hour, min: min, zone: zone)
    end

    it "reads a summer wall-clock time at the DST offset (+02:00)" do
      expect(resolve(Date.new(2026, 7, 1), 18, 0, "Europe/Amsterdam"))
        .to eq(Time.utc(2026, 7, 1, 16, 0, 0))
    end

    it "reads a winter wall-clock time at the standard offset (+01:00)" do
      expect(resolve(Date.new(2026, 1, 1), 18, 0, "Europe/Amsterdam"))
        .to eq(Time.utc(2026, 1, 1, 17, 0, 0))
    end

    it "holds the wall-clock time steady on either side of a mid-event DST end" do
      # Clocks go back 03:00->02:00 on 2026-10-25. An 08:00 chore the day
      # before and the day after must both fire at local 08:00 — different
      # UTC instants (06:00 then 07:00), which is exactly the point.
      before = resolve(Date.new(2026, 10, 24), 8, 0, "Europe/Amsterdam")
      after = resolve(Date.new(2026, 10, 26), 8, 0, "Europe/Amsterdam")
      expect(before).to eq(Time.utc(2026, 10, 24, 6, 0, 0))
      expect(after).to eq(Time.utc(2026, 10, 26, 7, 0, 0))
    end

    it "resolves an ambiguous fall-back time to the earlier instant" do
      # 02:30 occurs twice on 2026-10-25; the earlier is still CEST (+02:00).
      expect(resolve(Date.new(2026, 10, 25), 2, 30, "Europe/Amsterdam"))
        .to eq(Time.utc(2026, 10, 25, 0, 30, 0))
    end

    it "pushes a spring-forward gap time past the gap" do
      # 02:30 does not exist on 2026-03-29 (clocks jump 02:00->03:00); it
      # becomes 03:30 CEST (+02:00) = 01:30 UTC.
      expect(resolve(Date.new(2026, 3, 29), 2, 30, "Europe/Amsterdam"))
        .to eq(Time.utc(2026, 3, 29, 1, 30, 0))
    end
  end
end
