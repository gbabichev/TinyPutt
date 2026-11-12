//
//  CampaignTable.swift
//  Tiny Putt
//
//  Written by the hole checker (Tools/HoleChecker). Each entry is a seed the checker proved
//  makes a finishable, distinct hole, with the world it was given and the par it worked out.
//  Do not edit by hand.
//

nonisolated enum CampaignTable {
    struct Entry: Sendable {
        let seed: UInt64
        let theme: Int
        let par: Int
        let template: Int
        /// The obstacle the checker asked for first (-1 for none), part of what the seed means.
        let middle: Int
    }

    /// Levels 11 and up (levels 1-10 are the hand-made holes).
    static let entries: [Entry] = [
        Entry(seed: 1100019, theme: 0, par: 3, template: 0, middle: 0),
        Entry(seed: 1200210, theme: 1, par: 3, template: 5, middle: -1),
        Entry(seed: 1300000, theme: 2, par: 3, template: 2, middle: 10),
        Entry(seed: 1400014, theme: 0, par: 3, template: 8, middle: 2),
        Entry(seed: 1500000, theme: 1, par: 4, template: 4, middle: 7),
        Entry(seed: 1600079, theme: 2, par: 3, template: 1, middle: 12),
        Entry(seed: 1700200, theme: 0, par: 4, template: 7, middle: -1),
        Entry(seed: 1800000, theme: 1, par: 3, template: 3, middle: 9),
        Entry(seed: 1900021, theme: 2, par: 3, template: 0, middle: 1),
        Entry(seed: 2000088, theme: 0, par: 3, template: 5, middle: 6),
        Entry(seed: 2100000, theme: 3, par: 3, template: 2, middle: 11),
        Entry(seed: 2200201, theme: 2, par: 3, template: 8, middle: -1),
        Entry(seed: 2300000, theme: 0, par: 3, template: 4, middle: 8),
        Entry(seed: 2400060, theme: 1, par: 3, template: 1, middle: 1),
        Entry(seed: 2500010, theme: 2, par: 3, template: 7, middle: 6),
        Entry(seed: 2600200, theme: 0, par: 3, template: 3, middle: -1),
        Entry(seed: 2700000, theme: 3, par: 3, template: 6, middle: 3),
        Entry(seed: 2800001, theme: 1, par: 4, template: 4, middle: 8),
        Entry(seed: 2900005, theme: 2, par: 3, template: 0, middle: 0),
        Entry(seed: 3000065, theme: 0, par: 4, template: 5, middle: 5),
        Entry(seed: 3100001, theme: 1, par: 3, template: 1, middle: 10),
        Entry(seed: 3200006, theme: 2, par: 4, template: 7, middle: 2),
        Entry(seed: 3300000, theme: 3, par: 3, template: 2, middle: 7),
        Entry(seed: 3400213, theme: 0, par: 3, template: 8, middle: -1),
        Entry(seed: 3500000, theme: 1, par: 3, template: 3, middle: 4),
        Entry(seed: 3600002, theme: 2, par: 4, template: 6, middle: 9),
        Entry(seed: 3700000, theme: 3, par: 3, template: 4, middle: 2),
        Entry(seed: 3800118, theme: 0, par: 4, template: 0, middle: 7),
        Entry(seed: 3900091, theme: 2, par: 4, template: 5, middle: 12),
        Entry(seed: 4000108, theme: 3, par: 4, template: 1, middle: 4),
        Entry(seed: 4100201, theme: 1, par: 3, template: 7, middle: -1),
        Entry(seed: 4200016, theme: 2, par: 4, template: 2, middle: 1),
        Entry(seed: 4300203, theme: 0, par: 3, template: 8, middle: -1),
        Entry(seed: 4400006, theme: 3, par: 4, template: 3, middle: 11),
        Entry(seed: 4500001, theme: 2, par: 4, template: 6, middle: 3),
        Entry(seed: 4600005, theme: 0, par: 4, template: 4, middle: 8),
        Entry(seed: 4700000, theme: 1, par: 4, template: 0, middle: 0),
        Entry(seed: 4800200, theme: 3, par: 3, template: 5, middle: -1),
        Entry(seed: 4900200, theme: 0, par: 3, template: 1, middle: -1),
        Entry(seed: 5000130, theme: 2, par: 5, template: 7, middle: 3),
    ]
}
