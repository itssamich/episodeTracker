//
//  show.swift
//  EpisodTracker
//
//  Created by Alex Klein on 8/12/22.
//

import Foundation
import FirebaseFirestoreSwift

struct Show: Identifiable, Codable{
    @DocumentID var id:String? = UUID().uuidString
    var showName, uid: String
    var epCount: Int
}
