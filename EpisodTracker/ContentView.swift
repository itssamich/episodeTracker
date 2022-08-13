//
//  ContentView.swift
//  EpisodTracker
//
//  Created by Alex Klein on 8/12/22.
//

import SwiftUI
import Firebase
import FirebaseFirestoreSwift

//Helps manage document states with the UI by handling heavy interactions with firebase that need to be going from the get go
class AppViewModel: ObservableObject{
    @Published var user: User? //A collection of data for the current signed in user
    @Published var userShows = [Show]() //The current users active list of shows
    
    //gathers user information and their list on initialization
    init() {
        getCurrentUser()
        getUsersList()
    }
    //makes a call to firebase using the currentUser identifier to gather data relating to their account and then saves it as a published variable to allow for observed variables to reference and interact with it
    func getCurrentUser(){
        guard let uid = FirebaseManager.shared.auth.currentUser?.uid else {return}
        
        FirebaseManager.shared.firestore.collection("users").document(uid).getDocument { [self] snapshot, err in
            if let err = err{
                print("Cant get current user",err)
                return
            }
            
            guard let userData = snapshot?.data() else {
                print("No data found")
                return}
            let uid = userData["uid"] as? String ?? ""
            let username = userData["username"] as? String ?? ""
            let email = userData["email"] as? String ?? ""
            self.user = User(uid: uid, username: username, email: email)
        }
    }
    //makes a call to firebase using the currentUser identifier to request specific data relating to their uid and then map said requested data into a Show object which is then fit into the userShows array
    func getUsersList(){
        guard let uid = FirebaseManager.shared.auth.currentUser?.uid else {return}
        
        FirebaseManager.shared.firestore.collection("shows").whereField("uid", isEqualTo: uid).addSnapshotListener { QuerySnapshot, err in
            guard let documents = QuerySnapshot?.documents else {
                print("no documents")
                return
            }
            self.userShows = documents.compactMap {(QueryDocumentSnapshot) -> Show? in
                return try? QueryDocumentSnapshot.data(as: Show.self)

            }
        }
        
    }
}


//The basic view
struct ContentView: View {
    @State var isSignedIn = true
    var body: some View {
        NavigationView{
            if(isSignedIn){
                mainPage(isSignedIn: self.$isSignedIn)
            }
            else{
                SignInView(isSignedIn: self.$isSignedIn)
            }
        }.preferredColorScheme(.dark)
                
    }
}
//The view involved with most user interactions, it's default state is the "home page" where you see a list of interactable objects that the user has added to their list
struct mainPage: View{
    @Binding var isSignedIn: Bool //A binding state that tracks whether the user is logged in, for this view, its use is exclusively to change it to false on signout
    @ObservedObject var viewModel = AppViewModel() //The observed var of the viewmodel
    
    //Deletes the selected object in a list from firebase by mapping out the offset to figure out what item is being deleted and get it's respective id to feed to firebase for deletion
    func deleteValue(at offsets: IndexSet){
        offsets.map {viewModel.userShows[$0]}.forEach{ show in
            guard let showId = show.id else {return}
            FirebaseManager.shared.firestore.collection("shows").document(showId).delete() {
                err in
                if let err = err{
                    print("Couldn't Delete Document: \(err)")
                }
                else{
                    print("Deleted Document")
                }
            }
        }
    }
    
    var body: some View {
            List{
                ForEach(viewModel.userShows){ show in
                    VStack{
                        HStack{
                            VStack{
                                Text(show.showName).font(.title2).underline()
                                HStack{
                                    Text("Episode: \(String(show.epCount))")
                                }
                            }
                            Spacer()
                            VStack{
                                HStack{//These need to be separated and given their functionality through on tap gestures because apple doesn't have complete functionality for multiple buttons in a list item
                                    VStack{//adds one to the episode count for the given item
                                        Button(action: {}) { Image(systemName: "plus").font(.title)}.onTapGesture{
                                            if(show.epCount > 1){
                                                FirebaseManager.shared.firestore.collection("shows").document(show.id ?? "").updateData(["epCount" : show.epCount + 1])
                                            }
                                        }
                                    }
                                    
                                    VStack{//removes one from the episode count for the given item as long as episode count is greater than 1
                                        Button(action: {}) { Image(systemName: "minus").font(.title)}.onTapGesture {
                                            
                                                if(show.epCount > 1){
                                                    FirebaseManager.shared.firestore.collection("shows").document(show.id ?? "").updateData(["epCount" : show.epCount - 1])
                                                }
                                        }
                                    }
                                }
                            }.border(Color(.secondarySystemBackground))
                        }
                        
                    }
                    //Wanted to test swipe actions while I was here
//                    .swipeActions(edge: .leading, allowsFullSwipe: true, content: {
//                        Button("Subtract"){
//                            FirebaseManager.shared.firestore.collection("shows").document(show.id ?? "").updateData(["epCount" : show.epCount - 1])
//                        }
//                    })
                }.onDelete(perform: deleteValue)
            }.toolbar{
                ToolbarItem(placement: .navigationBarLeading){
                    Button("Sign Out"){
                        isSignedIn = false
                        try? FirebaseManager.shared.auth.signOut()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing){
                    NavigationLink(destination: addItem(uid: viewModel.user?.uid ?? "")) {
                        Label("Add", systemImage: "plus")
                    }
                }
            }.navigationTitle(viewModel.user?.username ?? "")
    }
}
//the view that really shouldnt be a view but oh well, it is in charge with providing the users the ability to add items to their list
struct addItem: View{
    @Environment(\.presentationMode) var presentationMode
    @State var uid: String
    @State private var showName: String = ""
    @State private var epCount: String = "1"
    var body: some View {
        VStack{
            TextField("Show Name", text: $showName).padding(.all).background(Color(.secondarySystemBackground)).disableAutocorrection(true).textInputAutocapitalization(.none)
            TextField("Episode", text: $epCount).padding(.all).background(Color(.secondarySystemBackground)).disableAutocorrection(true).keyboardType(.numberPad)
            
            Button("Add To List"){
                let episodes = Int(epCount) ?? 1//casts epCount to int
                let show = Show(showName: showName, uid: uid, epCount: episodes)//defines a new show object to add to the database
                do {
                    let _ = try FirebaseManager.shared.firestore.collection("shows").addDocument(from: show)
                }
                catch{
                    print("Failed to Add")
                }
                presentationMode.wrappedValue.dismiss()
            }
        }
        
    }
}

//The view involved with giving a potential user the tools
struct SignUpView: View{
    @Binding var isSignedIn: Bool
    
    //used to make sure no obviously bad data is entered
    @State private var badUser: Bool = false
    @State private var badPass: Bool = false
    
    //user account values
    @State private var email: String = ""
    @State private var username: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    var body: some View {
        VStack{
            HStack(){
                TextField("Email", text: $email).padding(.all).background(Color(.secondarySystemBackground)).disableAutocorrection(true).textInputAutocapitalization(.none).keyboardType(.emailAddress)
            }
            HStack(){
                TextField("Username", text: $username  ).padding(.all).background(Color(.secondarySystemBackground)).disableAutocorrection(true).textInputAutocapitalization(.none)
            }
            HStack(){
                TextField("First Name", text: $firstName  ).padding(.all).background(Color(.secondarySystemBackground)).disableAutocorrection(true)
                TextField("Last Name", text: $lastName  ).padding(.all).background(Color(.secondarySystemBackground)).disableAutocorrection(true)
            }
            HStack(){
                SecureField("Password", text: $password).padding().background(Color(.secondarySystemBackground)).disableAutocorrection(true).textInputAutocapitalization(.none)
                SecureField("Confirm Password", text: $confirmPassword).padding().background(Color(.secondarySystemBackground)).disableAutocorrection(true).textInputAutocapitalization(.none)
            }

            Button("Create Account"){
                badUser = false
                badPass = false
                if(email == ""){
                    badUser = true
                    return
                }
                if(password == ""){
                    badPass = true
                    return
                }
                //makes sure that the user enters the same password twice
                if(confirmPassword == password){
                    FirebaseManager.shared.auth.createUser(withEmail: email, password: password) { result, err in
                        if let err = err {
                            print("Failed to create user ", err)
                            return
                        }
                        print("Created user:\(result?.user.uid ?? "")")
                        FirebaseManager.shared.auth.signIn(withEmail: email, password: password) { result, err in
                            if let err = err {
                                print("Failed to login user", err)
                                return
                            }
                            print("User Created \(result?.user.uid ?? "")")
                        }
                        
                        guard let uid = FirebaseManager.shared.auth.currentUser?.uid else {return}
                        let user = ["email": self.email,"firstName": self.firstName, "lastName": self.lastName, "uid": uid ,"username": self.username]
                        FirebaseManager.shared.firestore.collection("users").document(uid).setData(user)
                        
                        FirebaseManager.shared.auth.signIn(withEmail: email, password: password) { result, err in
                            if let err = err {
                                print("Failed to login user", err)
                                return
                            }
                            print("Yes \(result?.user.uid ?? "")")
                            isSignedIn = true
                    
                        }
                    }
                }
                else{
                    print("Add visual for not matching passwords")
                }
            }.padding()
        }.navigationTitle("Create Account")

    }
    
}
struct SignInView: View {
    @Binding var isSignedIn: Bool
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var badUser: Bool = false
    @State private var badPass: Bool = false
    
    @State private var msg: String = ""

    var body: some View {

            VStack(){
                Text(msg)
                HStack(){
                    TextField("Email", text: $email).padding(.all).background(Color(.secondarySystemBackground)).keyboardType(.emailAddress)
                }
                HStack(){
                
                    SecureField("Password", text: $password).padding().background(Color(.secondarySystemBackground))
                }
                
                Button("Sign In") {
                    badUser = false
                    badPass = false
                    if(email == ""){
                        badUser = true
                        return
                    }
                    if(password == ""){
                        badPass = true
                        return
                    }
                    FirebaseManager.shared.auth.signIn(withEmail: email, password: password) { result, err in
                        if let err = err {
                            print("Failed to login user", err)
                            self.msg = "Failed to login user: \(err.localizedDescription)"
                            return
                        }
                        print("User \(result?.user.uid ?? "") signed in")
                        isSignedIn = true
                        
                    }
                }
                
                NavigationLink(destination: SignUpView(isSignedIn: self.$isSignedIn), label: {Text("Sign Up")})
                
                .padding()
                
                Spacer()
            }.navigationTitle("Sign In")
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
