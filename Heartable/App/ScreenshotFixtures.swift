#if DEBUG
import SwiftUI

/// Debug-only screens for capturing marketing screenshots without an account.
/// Launch the simulator build with `-HeartableScreenshot <name>`; only the
/// mixtape editor and vinyl shelf are available. Nothing here ships in Release.
enum ScreenshotFixtures {
    static var requested: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-HeartableScreenshot"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    static let recipientName = "Ava"

    static func mixtape() -> MixtapeDetailDTO {
        let mixtapeID = UUID(uuidString: "6E7A1C2B-4D5F-4A6B-8C9D-0E1F2A3B4C5D")!
        let owner = UUID()
        var tape = MixtapeDTO(
            id: mixtapeID, owner: owner,
            title: "Drive Home",
            description: "for the long way back, in the order we argued about them",
            coverUrl: "heartable-fixture://mixtape-scenery",
            createdAt: "2026-02-10T18:04:00Z",
            recipientId: UUID(),
            sentAt: "2026-02-14T09:12:00Z"
        )
        tape.mine = true
        // Songs from the owner's EXILE playlist, with Spotify's own artwork.
        let art = { (id: String) in "https://i.scdn.co/image/\(id)" }
        let rows: [[String: Any]] = [
            track("spotify:track:5xo8RrjJ9CVNrtRg2S3B1R", "Motion Sickness", "Phoebe Bridgers",
                  art("ab67616d0000b2736c26e4a2e4df94a55591c48f"), 229760,
                  note: "three times in a row on I-94, so it goes first"),
            track("spotify:track:57VAuR1WgKFzcpO3ujQx9A", "Harbor", "Clairo",
                  art("ab67616d0000b2732624442cf48e4962d1422da8"), 264011),
            track("spotify:track:5lExpsDwTE6hqMs5fJ8KRI", "Sailor Song", "Gigi Perez",
                  art("ab67616d0000b273fff34e4e82d7a20e5eaa83ba"), 211978,
                  note: "windows down, even in February"),
            track("spotify:track:1GNIYBU1XhMSlAxJXiUBbC", "Video Games", "Lana Del Rey",
                  art("ab67616d0000b27377a3afdbf4d24dd545105177"), 281946),
            track("spotify:track:7qEiBWlztvDFrILdizFULx", "Nice To Each Other", "Olivia Dean",
                  art("ab67616d0000b2739a336bfb6d40bbd90a507417"), 209000),
            track("spotify:track:3vkCueOmm7xQDoJ17W1Pm3", "My Love Mine All Mine", "Mitski",
                  art("ab67616d0000b27334f21d3047d85440dfa37f10"), 137773,
                  note: "you know why"),
        ]
        let data = try! JSONSerialization.data(withJSONObject: rows.enumerated().map { offset, row in
            var row = row
            row["position"] = offset
            row["mixtape_id"] = mixtapeID.uuidString
            return row
        })
        let tracks = try! JSONDecoder().decode([MixtapeTrackDTO].self, from: data)
        return MixtapeDetailDTO(mixtape: tape, tracks: tracks)
    }

    /// The landscape vinyl shelf: the first songs of the owner's real EXILE
    /// playlist, in order, as recorded in their Heartable backup.
    static let vinylPlaylist = UnifiedPlaylist(
        key: "spotify:exile", providerID: .spotify, playlistID: "exile",
        name: "EXILE", description: nil,
        image: URL(string: "https://image-cdn-ak.spotifycdn.com/image/ab67706c0000da84fd7b445a5a5f04299099b8aa"),
        trackCount: 196, owner: nil, contentRevision: "fixture"
    )

    static func vinylTracks() -> [UnifiedTrack] {
        exileTable.split(separator: "\n").map { line in
            let field = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return UnifiedTrack(
                key: "spotify:\(field[5])", providerID: .spotify, providerTrackID: field[5],
                uri: "spotify:track:\(field[5])",
                name: field[0], artists: [UnifiedArtist(id: "a-\(field[1])", name: field[1])],
                album: field[2], albumArt: URL(string: "https://i.scdn.co/image/\(field[3])"), durationMs: Int(field[4]) ?? 0
            )
        }
    }

    /// EXILE as backed up: song, artist, album, Spotify art ID, duration (ms), Spotify track ID.
    private static let exileTable = """
Loving	Land of Talk	Life After Youth	ab67616d0000b2734e443b6f005c0ba1315afd19	228506	7dxakwRz7PgqdohuXnV4ki
Charming	Genevieve Stokes	Hiding Places	ab67616d0000b27369db876db91cac92dc3c7188	117149	1F8Eyub1xiZVqlju2PMkFG
Medicine	Genevieve Stokes	Hiding Places	ab67616d0000b27369db876db91cac92dc3c7188	128665	5Xj5nw00ibMbVRLczXrdGA
Poltergeist	Genevieve Stokes	Hiding Places	ab67616d0000b27369db876db91cac92dc3c7188	225027	7sQqFfaHs0gXUNlasnGklr
Never in Love	Genevieve Stokes	Hiding Places	ab67616d0000b27369db876db91cac92dc3c7188	165782	12zMISWKPX9HqBx871hlOL
Desert Eagle	Genevieve Stokes	With a Lightning Strike	ab67616d0000b27395f122e0abd1dbd93baaf3cf	134529	41M54m8xSCcSwcBE3MLdMw
Dreamer	Genevieve Stokes	With a Lightning Strike	ab67616d0000b27395f122e0abd1dbd93baaf3cf	222549	7stBqkSq9DRrN6Xf5bM7cN
Old Friend	Genevieve Stokes	With a Lightning Strike	ab67616d0000b27395f122e0abd1dbd93baaf3cf	137362	3Xlsrm9vEpGlTzqfITLMO8
i don't know you anymore	sombr	i don't know you anymore	ab67616d0000b2738759a680ee50e7150e40e052	227756	5FCMqNc9fodjQRIXbG7Ld1
Shine	Alice Phoebe Lou	Shelter	ab67616d0000b273b9000413b688d298a7ce999e	182862	4c9y4rk02Pk9SnThkGJEN9
New Love Cassette	Angel Olsen	All Mirrors	ab67616d0000b273ac145f375fe5a918e623b46f	206413	4JaLWmdTChliUG88ks6Prm
Best	Gracie Abrams	Good Riddance (Deluxe)	ab67616d0000b2730500294bb235c45c0a964d69	233499	5HO2RD12vZ5NcIdAULo43M
I know it won't work	Gracie Abrams	Good Riddance (Deluxe)	ab67616d0000b2730500294bb235c45c0a964d69	245629	33uKUpu9ZXsHhcxRLoxnWI
Where do we go now?	Gracie Abrams	Good Riddance (Deluxe)	ab67616d0000b2730500294bb235c45c0a964d69	243599	47oXF9VHCqabVcjd2gZBpa
Chemtrails Over The Country Club	Lana Del Rey	Chemtrails Over The Country Club	ab67616d0000b273ca929c6e766cb8591a286e0d	271176	7bPWdJgx8vek7S5i5yAtvG
bend	petal redd	bend	ab67616d0000b273241a4b2a656a22244e47f100	151851	7y4TnkbFLGd5BTrOVwDZ3P
Isimo	Bleachers	Bleachers	ab67616d0000b273cf623921ae5f92e45d575ae0	203134	3rNqa21S7XpJ5v1WjoAqee
Slush Puppy	Tommy Lefroy	Slush Puppy	ab67616d0000b273fbb1552ec840e498094ca97b	166221	5esPnS3J0c0x94yZuCxukj
I Wanna Get Better	Bleachers	Strange Desire	ab67616d0000b2734849278ce9876ebea7353d66	204520	1BwhFXqoIsePt21WyWIttb
where you are	NOVA ONE	secret princess	ab67616d0000b273fab0ea880ad79748552aaf98	152134	3ty1Tcud4DYRWZoYQTYx8D
Tears In The Typing Pool	Broadcast	Tender Buttons	ab67616d0000b273efeb5afb5e7bcb9c6660fe39	132160	2ckhAiLT5eV5blWvyDs8Lh
Wild Waters	Lael Neale	Altogether Stranger	ab67616d0000b273e2281ba530f21b8a3543ee8f	177489	4mCOeMoL2TtipRS7wQnQE8
I Am The River	Lael Neale	Star Eaters Delight	ab67616d0000b273489346e1ab87713fa274ba42	212533	4psqJzes2gUj6TlG83f42A
Slip Away	Lael Neale	Slip Away	ab67616d0000b2737ebe3194e817d1280bc0d33d	177081	62fKZbi5kAxd3fL0ZOoGQm
Nobody New	Solaice Fleur	Nobody New	ab67616d0000b27340f131f13e665a61356ca2bc	168087	1CeBbJpngbDTuDWD9QT1kH
Persona	Charli xcx	Music, Fashion, Film	ab67616d0000b273238e2ff91714a8db91b8a64d	157039	4HQMNDSYtXgZvsCHIsuWTS
The 1975	The 1975	Being Funny In A Foreign Language	ab67616d0000b2731f44db452a68e229650a302c	250900	7omxuGYsym1n2RlVf86OF9
Looking For Somebody (To Love)	The 1975	Being Funny In A Foreign Language	ab67616d0000b2731f44db452a68e229650a302c	178617	0eNfURq0r0oNSwFyw1VuVT
About You	The 1975	Being Funny In A Foreign Language	ab67616d0000b2731f44db452a68e229650a302c	326490	1fDFHXcykq4iw8Gg7s5hG9
Back To Me	The Marías	Back To Me	ab67616d0000b273a66ab2cbaebcc84ddd45a078	214800	4E0P1xs3JNmsNr5c5nFTZJ
Nobody New	The Marías	Back To Me	ab67616d0000b273a66ab2cbaebcc84ddd45a078	215200	4pwJ6OujVQL3IpCr8KeXIg
Nice To Each Other	Olivia Dean	The Art of Loving	ab67616d0000b2739a336bfb6d40bbd90a507417	209000	7qEiBWlztvDFrILdizFULx
So Easy (To Fall In Love)	Olivia Dean	The Art of Loving	ab67616d0000b2739a336bfb6d40bbd90a507417	169000	6sGIMrtIzQjdzNndVxe397
Let Alone The One You Love	Olivia Dean	The Art of Loving	ab67616d0000b2739a336bfb6d40bbd90a507417	186000	3Vd4fHzwS6pBS3muymjiDi
I've Seen It	Olivia Dean	The Art of Loving	ab67616d0000b2739a336bfb6d40bbd90a507417	126000	6tHVEMyRfxGgQuXRzl2yOF
Staying	Lizzy McAlpine	Older (and Wiser)	ab67616d0000b273f6d3cf584664ceeca1550f1f	151647	6Jp9tZ8NrwXcrhSIriiwAX
I Guess	Lizzy McAlpine	Older (and Wiser)	ab67616d0000b273ae8516f025f800e78b875d44	224410	2FrorYSAnoCrK1slpp99Hr
Drunk, Running	Lizzy McAlpine	Older (and Wiser)	ab67616d0000b273ae8516f025f800e78b875d44	245732	5RdcSV7pwz8UEMQORxyAvf
Better Than This	Lizzy McAlpine	Older (and Wiser)	ab67616d0000b273ae8516f025f800e78b875d44	214545	7KLFyoZmcIp6SMrLdd4nKd
Soccer Practice	Lizzy McAlpine	Older (and Wiser)	ab67616d0000b273ae8516f025f800e78b875d44	238090	72Y8v9ZjNI8mkCvqpUiaBO
Spring Into Summer	Lizzy McAlpine	Older (and Wiser)	ab67616d0000b273ae8516f025f800e78b875d44	262518	6oCXDaFZYL7sHnowv6pdXb
exile (feat. Bon Iver)	Taylor Swift, Bon Iver	folklore	ab67616d0000b27395f754318336a07e85ec59bc	285634	4pvb0WLRcMtbPGmtejJJ6y
my tears ricochet	Taylor Swift	folklore	ab67616d0000b27395f754318336a07e85ec59bc	255893	1MgV7FIyNxIG7WzMRJV5HC
It's Called: Freefall	Paris Paloma	It's Called: Freefall	ab67616d0000b273786f52db0c57eba5335f0ec6	158297	2IRjyyiU5P9WnmXJKcnwww
Fidelity	Regina Spektor	Begin to Hope (Special Edition)	ab67616d0000b2737fd2d3669c086850c0f766e8	226680	6GskIhdM6TN6EkPgeSjVfW
My Moon My Man	Feist	The Reminder	ab67616d0000b273b17d3cdd360973516ade9e6d	228360	5FFQbvn7055P1DvgJDdCBP
Habits	Genevieve Stokes	Habits (Demo)	ab67616d0000b273fafe08f63f3250a59e865858	134865	0qL3JquOSa7ErWX3RXfUgo
Fable	Gigi Perez	At The Beach, In Every Life (Extended)	ab67616d0000b273fff34e4e82d7a20e5eaa83ba	261005	6l5e7Q8uvIeksz19Avljqr
Sailor Song	Gigi Perez	At The Beach, In Every Life (Extended)	ab67616d0000b273fff34e4e82d7a20e5eaa83ba	211978	5lExpsDwTE6hqMs5fJ8KRI
I miss you, I’m sorry	Gracie Abrams	minor	ab67616d0000b27355c38bc34d1fe852f2657c2e	167538	4nyF5lmSziBAt7ESAUjpbx
First Love/Late Spring	Mitski	Bury Me At Makeout Creek	ab67616d0000b273e90db8983ebd43b776694179	278640	3sslYZcFKtUvIEWN9lADgr
The Cut That Always Bleeds	Conan Gray	Kid Krow	ab67616d0000b27388e3cda6d29b2552d4d6bc43	231920	7wTqEW5nrMhvyEhEyTnOMd
What Do You Like In Me	Nasty Cherry	What Do You Like In Me	ab67616d0000b273eabbfaa9655a37b3452804a0	204173	1CC3sbNapIE3ABGUdpp2oU
Free Now	Gracie Abrams	The Secret of Us (Deluxe)	ab67616d0000b2731dac3694b3289cd903cb3acf	214080	49vuwo7SLmzO207Z7djITp
I Love You, I'm Sorry	Gracie Abrams	The Secret of Us (Deluxe)	ab67616d0000b2731dac3694b3289cd903cb3acf	157146	5W4FHsvv4PwqC5gYzXyrLI
Lovesick Lobotomy	Earthgirl	Lovesick Lobotomy	ab67616d0000b273a5d4702a945b2dde5761629c	137142	75puZs3gEpjiauihNVJCgs
I Tried	Trey Gruber	Herculean House Of Cards	ab67616d0000b273e6b7b0a786162dab51973794	181237	1w2aDz9UxbazKIBtv4GdMW
Going Blue	Victoria Bigelow	Songs For No One Vol. 2	ab67616d0000b27339044fa0c94be996733d8fd4	181800	6BbcIRJTg9XbxLIkmL6zwa
The Kids	Victoria Bigelow	Songs For No One Vol. 2	ab67616d0000b27339044fa0c94be996733d8fd4	247416	0F3MIwSBiEnlYcIVzwy1Nx
What Was That	Lorde	Virgin	ab67616d0000b27323d41bf736920a032e222a78	209286	7hGCCQkdyF1MX6uk339uBS
Broken Glass	Lorde	Virgin	ab67616d0000b27323d41bf736920a032e222a78	194038	6xCKXznjcHv2hZWDA0pRIe
Fall in Love with You.	Montell Fish	JAMIE	ab67616d0000b27338900c29071fe12d7a0a13cc	132000	4kJT7Yj6Za01KfKHjb7mZE
And i'd go a thousand miles	Montell Fish	JAMIE	ab67616d0000b27338900c29071fe12d7a0a13cc	146000	4XAAxqgd94HLvDQWc0EkDa
Destroy Myself Just For You	Montell Fish	JAMIE	ab67616d0000b27338900c29071fe12d7a0a13cc	146000	40Fmr4mXhz4PtrMAPTnoXB
Petrol Fumes	Billy Nomates	Emergency Telephone	ab67616d0000b27319131ce7352247fe64d83d6f	250932	1KDNM8wkqmnsrIgtgyCtJc
Lost Boys	Phoebe Bridgers	Lost Weekend	ab67616d0000b27325a647ace83ba32770ab5d0f	254614	6eoIuFQSEXcwQqr0RnFdW8
Motion Sickness	Phoebe Bridgers	Stranger in the Alps	ab67616d0000b2736c26e4a2e4df94a55591c48f	229760	5xo8RrjJ9CVNrtRg2S3B1R
Mariners Apartment Complex	Lana Del Rey	Norman Fucking Rockwell!	ab67616d0000b273879e9318cb9f4e05ee552ac9	247150	6OG05bPAwUuV3OMvy2Vy1P
Norman fucking Rockwell	Lana Del Rey	Norman Fucking Rockwell!	ab67616d0000b273879e9318cb9f4e05ee552ac9	248934	3RIgHHpnFKj5Rni1shokDj
Venice Bitch	Lana Del Rey	Norman Fucking Rockwell!	ab67616d0000b273879e9318cb9f4e05ee552ac9	577199	3hwQhakFwm9soLEBnSDH17
Happiness is a butterfly	Lana Del Rey	Norman Fucking Rockwell!	ab67616d0000b273879e9318cb9f4e05ee552ac9	272485	3lG6OtGDsYAOALxEmubQQm
Music To Watch Boys To	Lana Del Rey	Honeymoon	ab67616d0000b273a3b3f48ca81acacb3ad4ec8a	290625	34rRFl0bz9PocxWuO2ca5J
Art Deco	Lana Del Rey	Honeymoon	ab67616d0000b273a3b3f48ca81acacb3ad4ec8a	295066	5jqNQZBwbZWQXPWfo0ygZF
Video Games	Lana Del Rey	Born To Die (Bonus Track Version)	ab67616d0000b27377a3afdbf4d24dd545105177	281946	1GNIYBU1XhMSlAxJXiUBbC
National Anthem	Lana Del Rey	Born To Die (Bonus Track Version)	ab67616d0000b27377a3afdbf4d24dd545105177	230533	1F96ZPH8sMhxRg0E8Nyzev
Radio	Lana Del Rey	Born To Die (Bonus Track Version)	ab67616d0000b27377a3afdbf4d24dd545105177	214586	04cYZCH74znS6dgdryrWLx
Summertime Sadness	Lana Del Rey	Born To Die (Bonus Track Version)	ab67616d0000b27377a3afdbf4d24dd545105177	264773	0l2HaL3nbp9AFJ428p4yaA
Say Yes To Heaven	Lana Del Rey	Say Yes To Heaven	ab67616d0000b273aa27708d07f49c82ff0d0dae	209156	6GGtHZgBycCgGBUhZo81xe
Someday - triple j Like A Version	Julia Jacklin	Someday (triple j Like A Version)	ab67616d0000b2737092a31f1adfa5f82675c55d	264908	7yHIhm47w7yPXbWrCU3NId
Two Birds	Regina Spektor	Far	ab67616d0000b273c06f8d26d1620c4689f8d46a	195840	2n0U2OG5d6TuW5mKx7YrC0
Calling The Shots	Jamie B.	Calling The Shots	ab67616d0000b27394501f47fd700ac16613f0f1	231382	2dv3Of18YpkVgDqf8QjBBf
Oxygen	Porch Light	Oxygen	ab67616d0000b273f945ae892b9e26ea79cf8370	182346	29fc1RinBg7npe9NtS4yDO
No One Noticed	The Marías	Submarine	ab67616d0000b2738aa339341a0b0c813909c831	236906	3siwsiaEoU4Kuuc9WKMUy5
I Lost a Friend	FINNEAS	Blood Harmony (Deluxe)	ab67616d0000b2733e21a8c14f533edf876be407	237020	1t6yzcLN3JFlQPW1WtQqmF
Let's Fall in Love for the Night	FINNEAS	Blood Harmony (Deluxe)	ab67616d0000b2733e21a8c14f533edf876be407	190348	4E8zFJtBkJxE4X3F1dyRKB
BIRDS OF A FEATHER	Billie Eilish	HIT ME HARD AND SOFT	ab67616d0000b27371d62ea7ea8a5be92d3c1f62	210373	6dOtVTDdiauQNBQEDOtlAB
Carla's Song	Harry Styles	Kiss All The Time. Disco, Occasionally.	ab67616d0000b27374959140f550b11049c18a38	253653	3QuRLv8zkIYH31O5VgEpmo
Taste Back	Harry Styles	Kiss All The Time. Disco, Occasionally.	ab67616d0000b27374959140f550b11049c18a38	221653	3xClevycpBON8bkyxFbAna
Bubble Gum	Clairo	Bubble Gum	ab67616d0000b2735d93417bde90e0bd951dab08	175960	3zksbXteOCeSusJ5Xltr3t
lacy	Olivia Rodrigo	GUTS (spilled)	ab67616d0000b2734063d624ebf8ff67bc3701ee	177212	5SShKhLCYFydCsO4L7ULMr
enough for you	Olivia Rodrigo	SOUR	ab67616d0000b273a91c10fe9472d9bd89802e5a	202826	2TOzTqQXNmR2zDJXihjZ2e
Eyes Blue Like The Atlantic, Pt. 2 (feat. Powfu, Alec Benjamin & Rxseboy)	Sista Prod, Powfu, Alec Benjamin, Rxseboy, Sarcastic Sounds	Eyes Blue Like The Atlantic, Pt. 2 (feat. Powfu, Alec Benjamin & Rxseboy)	ab67616d0000b273d78415a897ee9291ba35e6cc	156187	1eCTQhsNA31FcwyNcJcf86
made you sick	camille blackman	made you sick	ab67616d0000b273c35e421072a73ed262b37f56	174124	70HMVVsfSQILWalJrEhfai
death bed (coffee for your head)	Powfu, beabadoobee	death bed (coffee for your head)	ab67616d0000b273bf01fd0986a195d485922167	173333	7eJMfftS33KTjuF7lTsMCx
WESTWORLD	EVAN GIIA	WESTWORLD	ab67616d0000b2739f3ce9d1c873caf604ff3c1b	209223	6ZP2iPx7t4epRBAKWvRPt1
Good Looking	Suki Waterhouse	Good Looking	ab67616d0000b27343bff43a592efe047d2ab9ff	214800	0j3mqDTK4Z6lvrLzFCUUz6
Neon Signs	Suki Waterhouse	Milk Teeth	ab67616d0000b2733ec634678874418d43d1c3c6	193500	6JZj85Iz5sc4cGKvOefO7G
A melody, a lie	Helen Sun	talk with your Teeth	ab67616d0000b2732eb48a25701313d61b985475	188010	7bFfWgxKE95fgUKKZr0e13
Lullaby	Grace Ives	Janky Star	ab67616d0000b27317a7217a4ec88a9d15594eed	186866	0PiSok4AgEcnVSWSGiz86p
Every Star Shivers in the Dark	Lael Neale	Acquainted with Night	ab67616d0000b273bcad4202bc1bce5fdb561c37	332731	56hyqliBwT15WP1sCdOp4E
TV	Billie Eilish	Guitar Songs	ab67616d0000b2737a4781629469bb83356cd318	281380	3GYlZ7tbxLOxe6ewMNVTkw
Spider	Esther Rose	Safe to Run	ab67616d0000b2738893ad4fc91885022977f096	230522	5RyBqIGm2gRGIDSpq0cKFY
heart of the woods (ending theme)	In Love With a Ghost, Ukuletea	heart of the woods (ending theme)	ab67616d0000b273ee3cfe577ab95d734bad0940	193734	38YuwNZvCHCMgju2Z1EbO4
bad idea!	girl in red	bad idea!	ab67616d0000b27356446861fdfba8294f605f63	219638	57j65yC2HggQfmYNc6rdOK
we never made it to glasgow	Lexie Carroll	you look lovely when you're living	ab67616d0000b27354ed2b96b79c48fbd3c43159	169707	4LOm8NL8DYw7v7ZbO8b9ST
Home Sweet Home	The Favors, FINNEAS, Ashe	The Dream	ab67616d0000b273d5838e5434cf633a063976da	208268	56CqQv5oOJmu70guWHLTTx
Youth	Daughter	If You Leave	ab67616d0000b273b56cfba0331dc607f4add360	253013	2ubUxHP2XzxO2WmcF1dJCo
Somewhere Somehow	Oddnesse	Somewhere Somehow	ab67616d0000b27390cc862721401adbdf6388b3	164044	07w28JF0iYZsJREgD3906I
Blackout Drunk	Suki Waterhouse	Memoir of a Sparklemuffin	ab67616d0000b273a9b6153a531deea48b17b26b	148021	0PyN8JswfA5otVomw09V5Q
OMG	Suki Waterhouse	Memoir of a Sparklemuffin	ab67616d0000b273a9b6153a531deea48b17b26b	178569	5vYjTN8d0DZ2SosbKSx5Nj
Chaise Longue	Wet Leg	Wet Leg	ab67616d0000b2731ce49e09e09c4f4f54533a1e	196905	0nys6GusuHnjSYLW0PYYb7
Wet Dream	Wet Leg	Wet Leg	ab67616d0000b2731ce49e09e09c4f4f54533a1e	140080	260Ub1Yuj4CobdISTOBvM9
Loving You	Wet Leg	Wet Leg	ab67616d0000b2731ce49e09e09c4f4f54533a1e	219173	0hRJrlZwrnM7Oalx4GLElX
would've been you	sombr	would've been you	ab67616d0000b2734327577d7acfa1419d564a6a	183586	2U7svZUGvR4tfKdyxv9mXu
Everyone Adores You (at least I do)	Matt Maltese	Good Morning It's Now Tomorrow	ab67616d0000b2736230a85a940c9eeccd588a5c	203133	6klFWv2xDGeTDoiKTtx4hg
Lingering	Allegra Krieger	I Keep My Feet on the Fragile Plane	ab67616d0000b27339d59ece153ce3a7f86a55c5	203352	5KVt7MKnauSYpmLPzdEP3q
Backwards Directions	Abby Sage	Backwards Directions	ab67616d0000b273fc7404894640cfa39507a287	187072	5vbnQr1tWSSREmcIONIUm9
The Gold - Phoebe Bridgers Version	Manchester Orchestra, Phoebe Bridgers	The Gold (Phoebe Bridgers Version)	ab67616d0000b2738b54cdfa703cc0162b76dfb1	233226	7qcXUzPwoxSBFxjTbNrV0B
East of Eden	Zella Day	Kicker	ab67616d0000b27345108945892f2bae307486e1	186213	2Wc2tcQl7cPetPKeXH3GD3
Hypnotic	Zella Day	Kicker	ab67616d0000b27345108945892f2bae307486e1	176786	2zsWRxMcUdGjj8TnWkVKw0
Cool About It	boygenius, Julien Baker, Phoebe Bridgers, Lucy Dacus	the record	ab67616d0000b27343fc02bcfa7cd4e6bb66aa22	180000	5PJH1U5Iie893v48Fl9yaC
Not Strong Enough	boygenius, Julien Baker, Phoebe Bridgers, Lucy Dacus	the record	ab67616d0000b27343fc02bcfa7cd4e6bb66aa22	234933	09DR0sHnQUhHOiSNttc1mv
Unrequited Love	Ella Walton	Unrequited Love	ab67616d0000b2733cc8a1ab35ea3d5d4e77371a	196075	2KaKhzlzoVDeBBjFBIFKvm
Chemical Light	Josie Edwards	Greetings From Bleak St.	ab67616d0000b273bf6cd8670eab3ee1d9efa4a8	226041	3PpTiirc8IzcjqEwDyaBZK
I Bet on Losing Dogs	Mitski	Puberty 2	ab67616d0000b27342cb382726e956058bf73ed3	170240	2Co0IjcLTSHMtodwD4gzfg
anything	Adrianne Lenker	songs	ab67616d0000b2738ebe185fc4824bc6e568b511	202047	4PwWESSlTwzvw9B7bmtTLS
half return	Adrianne Lenker	songs	ab67616d0000b2738ebe185fc4824bc6e568b511	128700	1i8dJGpKO0xQiKGCVslJqB
not a lot, just forever	Adrianne Lenker	songs	ab67616d0000b2738ebe185fc4824bc6e568b511	250198	11hEwcy9LMEvzAlOYAFhkK
Some Are Lakes	Land of Talk	Some Are Lakes	ab67616d0000b273b594a30ddd7eb3cb5f9ec1e0	221120	2mWfnFZvXQ3CKEJ49xRu87
Two of Us On the Run	Lucius	Wildewoman	ab67616d0000b2734f9e22b3a508bea17359ca93	275628	1IOHe119sZrSycoomDnu7D
All Things Heavy	Mynolia	All Things Heavy	ab67616d0000b2730817bb6dcd54cbe6ae43c389	204109	7hSIg14Ex5CENirghUApH0
Merry Christmas, Please Don't Call	Bleachers	Merry Christmas, Please Don't Call	ab67616d0000b2737fbed05d7226834da74c652b	202132	0UOG0zUn7t8m8QcxfzR7AH
Pour Your Heart Out	Hildegard, Helena Deland, Ouri	Jour 1596	ab67616d0000b2735fb55d80b5a7f7a02028f423	190282	3N9ho4NMwJMJzlH0xa9AIJ
Post Break Up Sex	Sophia Garvey	Post Break Up Sex	ab67616d0000b27313723219e77143e4849aae8d	202282	2uG2Wkt1RpgtSHJYrecO5x
Night Shift	Lucy Dacus	Night Shift	ab67616d0000b27367e0f1e91ef6a8d7fc3cadf0	391829	6414jxyYquBi9sqmufnT0A
Many Moons	Janelle Monáe	Metropolis: The Chase Suite (Special Edition)	ab67616d0000b273b72cb7bed93d6e2fdf42cffe	327520	4WehxcnPTxouLdfQhqANb3
Mushaboom	Feist	Let It Die	ab67616d0000b2737eed089be836e66ce2c2b65d	224506	66olzBxCgKlpFRB1LKH5pO
Calling U Back	The Marías	CINEMA	ab67616d0000b273657d6776f64aa731c8d1748b	199906	5WVWQQpBJqljbZtxo19CxS
Heavy	The Marías	CINEMA	ab67616d0000b273657d6776f64aa731c8d1748b	253213	1ShRHPAiiIrh0arZbSFmx1
Who	My Ugly Clementine	Vitamin C	ab67616d0000b273bf765fd778613c17e0424e3e	181025	5ChsCz0T4RykLavAqqwzHv
Bite The Bullet!	Emma Foley	Bite The Bullet!	ab67616d0000b2735485553b6fa028e239d68849	171428	1e9yrSDXHrhwP7ZdBHEiFY
12 to 12	sombr	I Barely Know Her	ab67616d0000b2734229702de91cb3d3a4383302	242903	05od2qm2MTSKCHxy1GBp5W
back to friends	sombr	I Barely Know Her	ab67616d0000b2734229702de91cb3d3a4383302	199032	7qjZnBKE73H4Oxkopwulqe
crushing	sombr	I Barely Know Her	ab67616d0000b2734229702de91cb3d3a4383302	207334	2pQoErkcTbLdQLnUtMYvuZ
i wish i knew how to quit you	sombr	I Barely Know Her	ab67616d0000b2734229702de91cb3d3a4383302	232375	5Lfdb0KKLWKEns27p20uYt
undressed	sombr	I Barely Know Her	ab67616d0000b2734229702de91cb3d3a4383302	182088	0TFTAtCYhp2tQ9KcJIZb55
we never dated	sombr	I Barely Know Her	ab67616d0000b2734229702de91cb3d3a4383302	196931	0t1fdMrn7JOg9DDsT95bxt
Crimes	Ruth Radelet	Crimes	ab67616d0000b2731f6d53c0971b9bc36a135edc	247016	24ljWfDdetRi7fpAPJJeCB
watch	Billie Eilish	dont smile at me	ab67616d0000b273a9f6c04ba168640b48aa5795	177523	7eB1V5LvAdxCc7brfGhRRo
hostage	Billie Eilish	dont smile at me	ab67616d0000b273a9f6c04ba168640b48aa5795	229425	1WsEgieHsWWndAzLkmV105
everything i wanted	Billie Eilish	everything i wanted	ab67616d0000b273f2248cf6dad1d6c062587249	245425	3ZCTVFBt2Brf31RLEnCkWJ
Johnny got it right	Harriette	i heart the internet	ab67616d0000b2730b4f0c19fe7800729b4774a7	211693	0czzj4UljxKL4aYMFWpIfI
if u want	Keni Titus	mud on my superstars	ab67616d0000b273f6fb10dfe60e2e4c4d328c38	230400	3QD5ouNoYNQEQkOwlP1fIV
Like I Say (I runaway)	Nilüfer Yanya	My Method Actor	ab67616d0000b273cb53aff3036cf65df48f50f6	177475	7f57Tz3uydJkSuVsQ7sj4l
hi from me	Wet Leg	moisturizer (deluxe)	ab67616d0000b27330945c36c03f2f1c28904c3c	102883	60XzwYT67TQNhF5Bhu2sQR
mangetout	Wet Leg	moisturizer (deluxe)	ab67616d0000b27330945c36c03f2f1c28904c3c	204475	11UJppQztR5wurXhlYyggd
Krystal	Matt Maltese	Krystal	ab67616d0000b273f01251e6e914959ebbd88ae5	220244	5JJPfHpByZ66XsEyCNVi2p
My Love Mine All Mine	Mitski	The Land Is Inhospitable and So Are We	ab67616d0000b27334f21d3047d85440dfa37f10	137773	3vkCueOmm7xQDoJ17W1Pm3
Henry, come on	Lana Del Rey	Henry, come on	ab67616d0000b2734fb0b47e965f62951205cc5a	311269	6CYldrsUPBsiPtfLW4xZCl
Naked	FINNEAS	Naked	ab67616d0000b273ae120f86151f5b19d63e291e	167096	1aXWzWjj5Lchfm44Uet9nZ
As It Was	Harry Styles	Harry's House	ab67616d0000b27382ce362511fb3d9dda6578ee	167303	4Dvkj6JhhA12EX05fT7y2e
Getting Older	Billie Eilish	Happier Than Ever	ab67616d0000b2732a038d3bf875d23e4aeaa84e	244221	4HOryCnbme0zBnF8LWij3f
my future	Billie Eilish	Happier Than Ever	ab67616d0000b2732a038d3bf875d23e4aeaa84e	210005	3YUMWmx8EJq0DurfuIwoGh
1957	Milo Greene	Milo Greene	ab67616d0000b273c28532a3cfe74f77d064815d	204213	08cXy6KUizaAelYXtcew3w
Babyyy	Grace Ives	Really Hot	ab67616d0000b273ff80c6995f24d499e1c6a25b	106994	6lMxGGVsO1JAdzk0z6Q3Rh
You or Nothing Else	Grace Ives	Really Hot	ab67616d0000b273ff80c6995f24d499e1c6a25b	136309	2EYpGwH2MdqNgdon81Km2v
Electric Nights	Emmrose	Thorns	ab67616d0000b273af1e68b79e2741893b1aef48	221405	6peHmdLBmuMSeGwTJTvrO7
ur so pretty	Wasia Project	My Vine	ab67616d0000b273e3106bba7acc62bf99a61014	132000	1N6yLqYILv6h09MUcTIttf
cold car, i'm veering	24thankyou	Heliophilia	ab67616d0000b273a58f181da9b7069bcead5cab	207874	6uCBQfJkZve0XfHMGiNJYY
hotline (edit)	Billie Eilish	hotline (edit)	ab67616d0000b273c820a9669147be3addd7f221	60719	0WFryfbNKPXVtVQlz5dZ8H
You're Still The One	Okay Kaya	You're Still The One	ab67616d0000b2730b37ac077612a0fa1351d73d	164779	3P87k30Y8InwhW8Vx9YOZR
damn navy	Ella Woolsey	damn navy	ab67616d0000b273bd2fd6d080367b1ff7d3c670	148565	12fKxw1rVgSTC4dZZ7oK6h
Harbor	Clairo	Sling	ab67616d0000b2732624442cf48e4962d1422da8	264011	57VAuR1WgKFzcpO3ujQx9A
Momentary Sweetheart	Deb Never	Thank You For Attending	ab67616d0000b27325554c131b59a062dbaab46b	182400	17JNJLUFRa32XDPDbuIT91
Sweet Carolina	Lana Del Rey	Blue Banisters	ab67616d0000b2736946deb6f548e464b385ee0e	201779	1Hezl8gsPpfK3N2by41Wxb
Thunder	Lana Del Rey	Blue Banisters	ab67616d0000b2736946deb6f548e464b385ee0e	259466	4y9vLiQ9mQb6XNEtc4K6ou
Turning Green	Sweet Tooth	Turning Green	ab67616d0000b27360649e803ca01dee07c654dd	137267	4fGW1MKzkBvR6DJEbE5Kkb
right where you left me - bonus track	Taylor Swift	evermore (deluxe version)	ab67616d0000b27390fd9741e1838115cd90b3b6	245026	3zwMVvkBe2qIKDObWgXw4N
hate to be lame	Lizzy McAlpine, FINNEAS	five seconds flat	ab67616d0000b273d370fdc4dbc47778b9b667c3	156798	26MJjeJ0NSOQDKeZzrEFMl
reckless driving	Lizzy McAlpine, Ben Kessler	five seconds flat	ab67616d0000b273d370fdc4dbc47778b9b667c3	189247	5GpEHUNI0T7L7H3DnAaBXh
Love Me Not	Ravyn Lenae	Love Me Not / Love Is Blind	ab67616d0000b27333b05d358247bbe9971370f2	213466	1UNEuG9DYOWiikf00ayr52
Shut Up Kiss Me	Angel Olsen	MY WOMAN	ab67616d0000b273f7ab493ccab101b239a3d1f4	202200	3EEr6l5PYelwkrvvKX7N0X
Sexy to Someone	Clairo	Charm	ab67616d0000b273193c2fafdce8f116b5ca0a78	207795	3awweDjWIuXNMogMClJnvE
Nomad	Clairo	Charm	ab67616d0000b273193c2fafdce8f116b5ca0a78	225572	4WJPxTsvWIdRZ9vMtqk7fj
Absence	DYAN	Midwest	ab67616d0000b2739fa819b7ad4b41c64a2e3697	280000	0jAuJrlhPdmLamXOrnRWat
Honey	Drugdealer, Weyes Blood	Raw Honey	ab67616d0000b273ce468a1ffdea6162fcdb106a	268146	2kPYU6yN0LfBZC67J45MJg
Wild Motion	Drugdealer, Dougie Poole	Raw Honey	ab67616d0000b273ce468a1ffdea6162fcdb106a	292986	0bRNQxQ8AfDXN7GAJ7ajXH
Cadillac	Sophie May	You Do Not Have To Be Good	ab67616d0000b27348d0873c8760b6d7d14eb787	171481	16vuy4pwheYCxp2Pyv3YRy
Lover Boy	Sophie May	You Do Not Have To Be Good	ab67616d0000b27348d0873c8760b6d7d14eb787	119645	698zM4fC45zI9Rb5XqJ6FS
Selfish Soul	Sudan Archives	Natural Brown Prom Queen	ab67616d0000b2739c351edcaee4de7d242e7aea	142666	3XqP0HAPdDN3Lkdoufds20
Docket (feat. Bully)	Blondshell, Bully	Docket (feat. Bully)	ab67616d0000b273f408df7d59dbee64da13a5fa	210493	64Js3amhV3Pa7ho3Io1PM1
Bruises & Scratches	Sophie May	With The Band / Bruises & Scratches	ab67616d0000b273e3ead813ae85247e153fccd2	139904	1E3vswBWNDxpJcopj8E7iB
No More Birthdays	Sophie May	No More Birthdays	ab67616d0000b273608ffc721bc2f099b67bf392	143329	07vhmVKuG3i96RtFlC9xEH
Mirror	Grace Ives	2nd	ab67616d0000b2732adacf8283d1242a6bd2d942	115927	3xzNx6376GxNDor46whFE6
How Will I Know	Bully	Lucky For You	ab67616d0000b2730e10e3ce5c735a10b665a7d5	191160	1cBNHQHbdcBV5mZ88FhO0V
Suburbia	Moody Joody	Suburbia	ab67616d0000b273a379d459a43d060f36f1b29c	214597	5zYpWznknMJkx7ovNZLbuk
"""

    private static func track(_ uri: String, _ name: String, _ artist: String, _ art: String, _ duration: Int,
                              note: String? = nil, photo: String? = nil) -> [String: Any] {
        var row: [String: Any] = [
            "id": UUID().uuidString, "track_uri": uri, "track_name": name, "artist": artist,
            "album_art": art, "duration_ms": duration, "skip_regions": [],
        ]
        if let note { row["note"] = note }
        if let photo { row["note_image_url"] = photo }
        return row
    }
}
extension ScreenshotFixtures {
    static let viewerID = UUID(uuidString: "5B0E7F6A-2C1D-4E3F-9A8B-7C6D5E4F3A21")!
    static let friendID = UUID(uuidString: "A7A00000-1C2D-4E5F-8A9B-0C1D2E3F4A5B")!
    static let friendName = "Ava"

    struct FriendProfile {
        let profile: ProfileDTO
        let nowPlaying: FriendNowPlayingDTO
        let board: [LeaderboardEntryDTO]
        let songBoard: [SongLeaderboardEntryDTO]
    }

    /// A friend's profile, fed through the view's own rank, rotation and
    /// compatibility logic. Every song is from the owner's EXILE playlist.
    static func friendProfile() -> FriendProfile {
        let viewer = viewerID.uuidString.lowercased(), friend = friendID.uuidString.lowercased()
        func entry(_ id: String, _ name: String, _ artist: String, _ plays: Int, _ who: [String]) -> SongLeaderboardEntryDTO {
            SongLeaderboardEntryDTO(trackUri: "spotify:track:\(id)", trackName: name, artist: artist, plays: plays,
                                    contributors: who.map { SongLeaderboardContributorDTO(userId: $0, displayName: nil, avatarUrl: nil) })
        }
        let songBoard = [
            entry("5lExpsDwTE6hqMs5fJ8KRI", "Sailor Song", "Gigi Perez", 41, [friend, viewer]),
            entry("7qEiBWlztvDFrILdizFULx", "Nice To Each Other", "Olivia Dean", 33, [friend]),
            entry("57VAuR1WgKFzcpO3ujQx9A", "Harbor", "Clairo", 27, [friend, viewer]),
            entry("5xo8RrjJ9CVNrtRg2S3B1R", "Motion Sickness", "Phoebe Bridgers", 25, [viewer]),
            entry("7qjZnBKE73H4Oxkopwulqe", "back to friends", "sombr", 22, [friend]),
            entry("3vkCueOmm7xQDoJ17W1Pm3", "My Love Mine All Mine", "Mitski", 19, [friend, viewer]),
            entry("1GNIYBU1XhMSlAxJXiUBbC", "Video Games", "Lana Del Rey", 18, [viewer]),
            entry("3zksbXteOCeSusJ5Xltr3t", "Bubble Gum", "Clairo", 14, [friend]),
            entry("7dxakwRz7PgqdohuXnV4ki", "Loving", "Land of Talk", 12, [viewer]),
        ]
        let board = try! JSONDecoder().decode([LeaderboardEntryDTO].self, from: Data("""
        [{"user_id": "\(viewerID)", "display_name": "You", "tracks": 268, "minutes": 912, "is_me": true},
         {"user_id": "\(friendID)", "display_name": "\(friendName)", "tracks": 214, "minutes": 731}]
        """.utf8))
        let profile = try! JSONDecoder().decode(ProfileDTO.self, from: Data("""
        {"user_id": "\(friendID)", "display_name": "\(friendName)", "handle": "ava", "spotify_id": "ava"}
        """.utf8))
        let nowPlaying = FriendNowPlayingDTO(
            userId: friendID, displayName: friendName, avatarUrl: nil,
            trackName: "Sailor Song", artist: "Gigi Perez",
            albumArt: "https://i.scdn.co/image/ab67616d0000b273fff34e4e82d7a20e5eaa83ba",
            isPlaying: true, updatedAt: ISO8601DateFormatter().string(from: .now)
        )
        return FriendProfile(profile: profile, nowPlaying: nowPlaying, board: board, songBoard: songBoard)
    }
}

/// A friend's profile, pushed from the friends list the way people reach it.
struct ScreenshotFriendView: View {
    @Environment(ThemeStore.self) private var theme
    @State private var path = ["friend"]

    var body: some View {
        NavigationStack(path: $path) {
            theme.palette.bg.ignoresSafeArea()
                .navigationTitle("Friends")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: String.self) { _ in
                    FriendProfileView(userId: ScreenshotFixtures.friendID, displayName: ScreenshotFixtures.friendName, avatarUrl: nil)
                }
        }
        .tint(theme.palette.text)
        .preferredColorScheme(theme.current.group == .dark ? .dark : .light)
    }
}

/// Render the editor as a pushed screen, just like opening a saved mixtape.
/// A navigation root omits Back and gives the toolbar different geometry.
struct ScreenshotMixtapeView: View {
    @Environment(ThemeStore.self) private var theme
    @State private var path = ["mixtape"]
    private let fixture = ScreenshotFixtures.mixtape()

    var body: some View {
        NavigationStack(path: $path) {
            theme.palette.bg.ignoresSafeArea()
                .navigationTitle("Mixtapes")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: String.self) { _ in
                    MixtapeEditorView(
                        mixtapeID: fixture.mixtape.id,
                        recipientName: ScreenshotFixtures.recipientName,
                        fixture: fixture
                    )
                }
        }
        .tint(theme.palette.text)
        .preferredColorScheme(theme.current.group == .dark ? .dark : .light)
    }
}
struct ScreenshotVinylView: View {
    @Environment(ThemeStore.self) private var theme
    @State private var path = ["vinyl"]
    @State private var tracks = PlaylistTracksRepository(
        fetch: { _ in .success(ScreenshotFixtures.vinylTracks()) }, persistenceEnabled: false
    )

    var body: some View {
        NavigationStack(path: $path) {
            theme.palette.bg.ignoresSafeArea()
                .navigationTitle("Library")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: String.self) { _ in
                    PlaylistDetailView(playlist: ScreenshotFixtures.vinylPlaylist, ownership: .friend)
                }
        }
        .environment(tracks)
        .tint(theme.palette.text)
        .preferredColorScheme(theme.current.group == .dark ? .dark : .light)
    }
}
#endif
