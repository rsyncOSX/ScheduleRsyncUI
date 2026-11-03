//
//  TableofNotExeSchedules.swift
//  RsyncUI
//
//  Created by Thomas Evensen on 19/10/2025.
//

import SwiftUI

struct TableofNotExeSchedules: View {
    @Binding var selecteduuids: Set<ScheduledItem.ID>

    var body: some View {
        Table(GlobalTimer.shared.notExecutedSchedulesafterWakeUp, selection: $selecteduuids) {
            TableColumn("Profile") { data in
                Text(data.scheduledata?.profile ?? "Default")
            }
            .width(min: 80, max: 120)

            TableColumn("Schedule") { data in
                Text(data.scheduledata?.scheduleDescription ?? "")
            }
            .width(min: 100, max: 150)

            TableColumn("Run") { data in
                Text(data.time, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                    .help(data.time.formatted(date: .complete, time: .shortened))
            }
            .width(min: 150, ideal: 165, max: 190)
        }
    }
}
