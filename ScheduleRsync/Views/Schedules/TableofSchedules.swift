//
//  TableofSchedules.swift
//  Calendar
//
//  Created by Thomas Evensen on 25/03/2025.
//

import SwiftUI

struct TableofSchedules: View {
    @Binding var selecteduuids: Set<ScheduledItem.ID>

    var body: some View {
        Table(GlobalTimer.shared.displayedSchedules, selection: $selecteduuids) {
            TableColumn("Profile") { data in
                Text(data.scheduledata?.profile ?? "Default")
                    .foregroundStyle(data.skipReason != nil ? Color.red : (data.isAdjusted ? Color.yellow : Color.primary))
            }
            .width(min: 80, max: 200)

            TableColumn("Run") { data in
                Text(data.time, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .foregroundStyle(data.skipReason != nil ? Color.red : (data.isAdjusted ? Color.yellow : Color.primary))
                    .help(data.time.formatted(date: .complete, time: .shortened))
            }
            .width(min: 150, ideal: 165, max: 190)

            TableColumn("Status") { data in
                Text(data.skipReason ?? (data.isAdjusted ? "Adjusted" : "Scheduled"))
                    .foregroundStyle(data.skipReason != nil ? Color.red : (data.isAdjusted ? Color.yellow : Color.secondary))
                    .help("Requested: \(data.requestedTime.formatted(date: .abbreviated, time: .shortened))")
            }
            .width(min: 100, ideal: 180)
        }
    }
}
