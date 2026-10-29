import Foundation

struct TestServer:Identifiable {
    let id:String
    let name:String
    let location:String
    let download:String
    var upload:String? = nil
    let source:String
    var label:String { "\(name) · \(location) · \(upload == nil ? "↓ скачивание" : "↓↑ оба направления")" }
    static let all:[TestServer] = [
        .init(id:"rastr",name:"RastrNet",location:"Красноярск",download:"http://speedtest.rastrnet.ru/1GB.zip",upload:"http://speedtest.rastrnet.ru/speedtest/upload.php",source:"https://speedtest.rastrnet.ru/"),
        .init(id:"selectel",name:"Selectel",location:"Россия",download:"https://speedtest.selectel.ru/1GB",source:"https://selectel.ru/speedtest/"),
        .init(id:"wcloud",name:"WCloud",location:"Россия",download:"https://speedtest.wcloud.ru/1GB",source:"https://speedtest.wcloud.ru/"),
        .init(id:"true",name:"Truenetwork",location:"Новокузнецк",download:"https://mirror.truenetwork.ru/speedtest/1GiB",source:"https://speedtest.rastrnet.ru/"),
        .init(id:"eka",name:"EKACOD",location:"Екатеринбург",download:"https://lg.ekacod.ru/1000MB.test",source:"https://lg.ekacod.ru/"),
        .init(id:"serv",name:"serv.host",location:"Москва",download:"https://msk.lg.serv.host/files/1GB",source:"https://serv.host/speed-check/"),
        .init(id:"edis-msk",name:"EDIS",location:"Москва",download:"https://ru.edisglobal.com/1000MB.test",source:"https://ru.edisglobal.com/"),
        .init(id:"edis-spb",name:"EDIS",location:"Санкт-Петербург",download:"https://rusp.edisglobal.com/1000MB.test",source:"https://rusp.edisglobal.com/"),
        .init(id:"profit-msk",name:"ProfitServer",location:"Москва",download:"https://b250dc701ca686615a7c463b29b7f8ed.ip.looking.house/100.mb",source:"https://profitserver.net/datacenters/"),
        .init(id:"profit-chk",name:"ProfitServer",location:"Челябинск",download:"https://fa9b5207f1aa299046b3af5e5790098b.ip.looking.house/100.mb",source:"https://profitserver.net/datacenters/"),
        .init(id:"eserver",name:"eServer",location:"Москва",download:"https://lg.ru.eserver.net/test/1GB.bin",source:"https://www.eserver.ru/cart.php?gid=18&language=spanish"),
        .init(id:"virty",name:"Virty",location:"Санкт-Петербург",download:"http://lg.spb.virty.io/1000MB.test",source:"https://virty.io/ru/docs/dc/")
    ]
}
