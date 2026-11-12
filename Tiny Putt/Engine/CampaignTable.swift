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
        Entry(seed: 1200010, theme: 2, par: 3, template: 5, middle: 7),
        Entry(seed: 1300000, theme: 1, par: 3, template: 2, middle: 14),
        Entry(seed: 1400316, theme: 0, par: 3, template: 8, middle: -1),
        Entry(seed: 1500000, theme: 2, par: 4, template: 4, middle: 2),
        Entry(seed: 1600002, theme: 1, par: 3, template: 1, middle: 9),
        Entry(seed: 1700002, theme: 0, par: 3, template: 7, middle: 16),
        Entry(seed: 1800001, theme: 2, par: 3, template: 3, middle: 23),
        Entry(seed: 1900308, theme: 1, par: 3, template: 0, middle: -1),
        Entry(seed: 2000311, theme: 0, par: 3, template: 5, middle: -1),
        Entry(seed: 2100001, theme: 2, par: 3, template: 2, middle: 18),
        Entry(seed: 2200312, theme: 1, par: 3, template: 8, middle: -1),
        Entry(seed: 2300001, theme: 0, par: 4, template: 4, middle: 6),
        Entry(seed: 2400004, theme: 2, par: 3, template: 1, middle: 13),
        Entry(seed: 2500000, theme: 1, par: 3, template: 7, middle: 20),
        Entry(seed: 2600019, theme: 0, par: 4, template: 3, middle: 1),
        Entry(seed: 2700009, theme: 2, par: 3, template: 6, middle: 8),
        Entry(seed: 2800004, theme: 1, par: 4, template: 4, middle: 15),
        Entry(seed: 2900004, theme: 0, par: 3, template: 0, middle: 22),
        Entry(seed: 3000172, theme: 2, par: 4, template: 5, middle: 3),
        Entry(seed: 3100001, theme: 1, par: 3, template: 1, middle: 10),
        Entry(seed: 3200005, theme: 0, par: 4, template: 7, middle: 17),
        Entry(seed: 3300000, theme: 3, par: 3, template: 2, middle: 24),
        Entry(seed: 3400207, theme: 2, par: 3, template: 8, middle: 5),
        Entry(seed: 3500000, theme: 0, par: 3, template: 3, middle: 12),
        Entry(seed: 3600022, theme: 1, par: 4, template: 6, middle: 19),
        Entry(seed: 3700000, theme: 2, par: 3, template: 4, middle: 1),
        Entry(seed: 3800204, theme: 0, par: 3, template: 0, middle: 8),
        Entry(seed: 3900091, theme: 1, par: 4, template: 5, middle: 15),
        Entry(seed: 4000206, theme: 2, par: 3, template: 1, middle: 22),
        Entry(seed: 4100016, theme: 0, par: 4, template: 7, middle: 3),
        Entry(seed: 4200082, theme: 1, par: 4, template: 2, middle: 10),
        Entry(seed: 4300118, theme: 2, par: 4, template: 8, middle: 17),
        Entry(seed: 4400040, theme: 0, par: 4, template: 3, middle: 24),
        Entry(seed: 4500001, theme: 1, par: 4, template: 6, middle: 5),
        Entry(seed: 4600000, theme: 2, par: 4, template: 4, middle: 12),
        Entry(seed: 4700020, theme: 3, par: 4, template: 0, middle: 19),
        Entry(seed: 4800079, theme: 1, par: 4, template: 5, middle: 0),
        Entry(seed: 4900313, theme: 2, par: 3, template: 1, middle: -1),
        Entry(seed: 5000123, theme: 3, par: 4, template: 7, middle: 14),
    ]
}
