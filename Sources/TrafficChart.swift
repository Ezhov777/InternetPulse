import SwiftUI

enum ChartScale {
    static func ceiling(for peak:Double)->Double {
        let raw=max(1,peak*1.12)/4
        let power=pow(10,floor(log10(raw)))
        let step=([1.0,2,2.5,5,10].first{$0*power>=raw} ?? 10)*power
        return step*4
    }
}

struct TrafficChart:View {
    let samples:[Sample]
    let elapsed:String
    var peakDown:Double=0
    var peakUp:Double=0
    @State private var seconds=60.0
    @State private var hover:Double?
    var end:Date { samples.last?.date ?? Date() }
    var visible:[Sample] { samples.filter{$0.date>=end.addingTimeInterval(-seconds)} }
    var selected:Sample? {
        guard let fraction=hover else {return samples.last}
        let target=end.addingTimeInterval(-seconds*(1-fraction))
        return visible.min{abs($0.date.timeIntervalSince(target))<abs($1.date.timeIntervalSince(target))}
    }
    var period:String { seconds<60 ? L("{0} сек",String(Int(seconds))) : seconds<3600 ? L("{0} мин",String(Int(seconds/60))) : L("{0} ч",String(format:"%g",seconds/3600)) }
    var body:some View {
        VStack(alignment:.leading,spacing:20) {
            HStack(alignment:.firstTextBaseline) {
                Text(L("Скорость соединения")).font(.system(size:20,weight:.semibold)).tracking(-0.4)
                Spacer()
                HStack(spacing:4) {
                    zoomButton("minus",action:{seconds=min(86400,seconds*2)})
                    Picker(L("Интервал графика"),selection:$seconds) {
                        Text(L("30 сек")).tag(30.0);Text(L("1 мин")).tag(60.0);Text(L("5 мин")).tag(300.0)
                        Text(L("15 мин")).tag(900.0);Text(L("1 час")).tag(3600.0);Text(L("24 часа")).tag(86400.0)
                        if ![30.0,60,300,900,3600,86400].contains(seconds) {Text(period).tag(seconds)}
                    }.labelsHidden().pickerStyle(.menu).frame(width:110)
                    zoomButton("plus",action:{seconds=max(30,seconds/2)})
                }.padding(5).background(.white.opacity(0.035),in:Capsule())
            }
            HStack(alignment:.bottom,spacing:28) {
                metric(L("Скачивание"),value:selected?.down,color:mint,symbol:"arrow.down")
                metric(L("Отдача"),value:selected?.up,color:blue,symbol:"arrow.up")
                Spacer()
                VStack(alignment:.trailing,spacing:6) {
                    Text(hover==nil ? L("ПОСЛЕДНИЙ ЗАМЕР") : L("ВЫБРАННЫЙ ЗАМЕР")).font(.system(size:8,weight:.medium,design:.monospaced)).tracking(1).foregroundStyle(.secondary)
                    Text(selected?.date.formatted(.dateTime.hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits)) ?? "—")
                        .font(.system(size:12,design:.monospaced)).foregroundStyle(.secondary)
                }
            }
            ChartCanvas(samples:visible,end:end,seconds:seconds,selected:hover==nil ? nil : selected)
                .frame(height:215)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): hover=max(0,min(1,(point.x-48)/max(1,chartWidth-60)))
                    case .ended: hover=nil
                    }
                }
                .background(GeometryReader { geometry in Color.clear.onAppear {chartWidth=geometry.size.width}.onChange(of:geometry.size.width) {_,value in chartWidth=value} })
                .accessibilityLabel(L("График скорости: вертикальная ось — мегабиты в секунду, горизонтальная — время"))
            HStack {
                Label(L("Рекорды сессии"),systemImage:"trophy").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary)
                Text("↓ \(TrafficFormat.speed(peakDown)) \(L("Мбит/с"))").foregroundStyle(mint)
                Text("↑ \(TrafficFormat.speed(peakUp)) \(L("Мбит/с"))").foregroundStyle(blue)
                Spacer()
                Text(L("Максимум секундных замеров")).foregroundStyle(.secondary)
            }.font(.system(size:10,design:.monospaced))
            HStack {
                Label(L("Наведите на график, чтобы увидеть замер"),systemImage:"cursorarrow.rays").font(.system(size:10)).foregroundStyle(.secondary)
                Spacer()
                Text(L("Время теста  {0}",elapsed)).font(.system(size:10,design:.monospaced)).foregroundStyle(.secondary)
            }
        }.padding(24).modifier(GlassPanel())
    }
    @State private var chartWidth:CGFloat=700
    func zoomButton(_ symbol:String,action:@escaping ()->Void)->some View {
        Button(action:action) {Image(systemName:symbol).font(.system(size:12,weight:.medium)).frame(width:28,height:28)}
            .buttonStyle(.plain).background(.white.opacity(0.04),in:Circle())
            .help(symbol=="plus" ? L("Приблизить график") : L("Показать больший интервал"))
    }
    func metric(_ title:String,value:Double?,color:Color,symbol:String)->some View {
        VStack(alignment:.leading,spacing:8) {
            Label(L(title),systemImage:symbol).font(.system(size:11,weight:.medium)).foregroundStyle(color)
            HStack(alignment:.firstTextBaseline,spacing:6) {
                Text(value.map{TrafficFormat.speed($0)} ?? "—").font(.system(size:26,weight:.light,design:.rounded)).monospacedDigit().foregroundStyle(.white)
                Text(L("Мбит/с")).font(.system(size:10)).foregroundStyle(.secondary)
            }
        }.frame(minWidth:135,alignment:.leading)
    }
}

struct ChartCanvas:View {
    let samples:[Sample]
    let end:Date
    let seconds:Double
    let selected:Sample?
    var body:some View {
        Canvas { context,size in
            let left:CGFloat=48,right:CGFloat=12,top:CGFloat=26,bottom:CGFloat=27
            let width=max(1,size.width-left-right),height=max(1,size.height-top-bottom)
            let start=end.addingTimeInterval(-seconds)
            let maximum=ChartScale.ceiling(for:samples.reduce(0){max($0,$1.down,$1.up)})
            let step=max(1,samples.count/1500)
            let points=samples.enumerated().filter{$0.offset%step==0 || $0.offset==samples.count-1}.map{$0.element}
            context.draw(Text(L("Мбит/с")).font(.system(size:10,weight:.medium)).foregroundColor(.white.opacity(0.5)),at:CGPoint(x:0,y:5),anchor:.topLeading)
            for i in 0...4 {
                let y=top+height*CGFloat(i)/4
                var line=Path();line.move(to:CGPoint(x:left,y:y));line.addLine(to:CGPoint(x:size.width-right,y:y))
                context.stroke(line,with:.color(.white.opacity(i==4 ? 0.12 : 0.045)),style:StrokeStyle(lineWidth:1,dash:i==4 ? [] : [3,5]))
                let value=maximum*(1-Double(i)/4)
                context.draw(Text(String(format:"%g",locale:AppLanguage.shared.locale,value)).font(.system(size:10,design:.monospaced)).foregroundColor(.white.opacity(0.4)),at:CGPoint(x:left-12,y:y),anchor:.trailing)
            }
            for i in 0...4 {
                let x=left+width*CGFloat(i)/4
                let date=start.addingTimeInterval(seconds*Double(i)/4)
                let text=date.formatted(.dateTime.hour(.twoDigits(amPM:.omitted)).minute(.twoDigits).second(.twoDigits))
                context.draw(Text(text).font(.system(size:9,design:.monospaced)).foregroundColor(.white.opacity(0.35)),at:CGPoint(x:x,y:size.height-5),anchor:i==0 ? .bottomLeading : i==4 ? .bottomTrailing : .bottom)
            }
            func point(_ sample:Sample,_ direction:Int)->CGPoint {
                CGPoint(x:left+width*CGFloat(sample.date.timeIntervalSince(start)/seconds),y:top+height*(1-CGFloat((direction==0 ? sample.down : sample.up)/maximum)))
            }
            for direction in 0...1 {
                let color=direction==0 ? mint : blue
                var path=Path()
                for (index,sample) in points.enumerated() {
                    if index==0 {path.move(to:point(sample,direction))} else {path.addLine(to:point(sample,direction))}
                }
                if let first=points.first,let last=points.last {
                    var area=path
                    area.addLine(to:CGPoint(x:point(last,direction).x,y:top+height))
                    area.addLine(to:CGPoint(x:point(first,direction).x,y:top+height));area.closeSubpath()
                    context.fill(area,with:.linearGradient(Gradient(colors:[color.opacity(direction==0 ? 0.16 : 0.09),color.opacity(0)]),startPoint:CGPoint(x:0,y:top),endPoint:CGPoint(x:0,y:top+height)))
                    context.stroke(path,with:.color(color.opacity(0.07)),style:StrokeStyle(lineWidth:7,lineCap:.round,lineJoin:.round))
                    context.stroke(path,with:.color(color),style:StrokeStyle(lineWidth:2,lineCap:.round,lineJoin:.round))
                    let dot=point(selected ?? last,direction)
                    context.fill(Path(ellipseIn:CGRect(x:dot.x-5,y:dot.y-5,width:10,height:10)),with:.color(color.opacity(0.13)))
                    context.fill(Path(ellipseIn:CGRect(x:dot.x-2.5,y:dot.y-2.5,width:5,height:5)),with:.color(color))
                }
            }
            if let sample=selected {
                let x=point(sample,0).x
                var line=Path();line.move(to:CGPoint(x:x,y:top));line.addLine(to:CGPoint(x:x,y:top+height))
                context.stroke(line,with:.color(.white.opacity(0.25)),style:StrokeStyle(lineWidth:1,dash:[3,4]))
            }
            if samples.count<2 {
                context.draw(Text(L("Здесь появится скорость вашего соединения")).font(.system(size:12)).foregroundColor(.white.opacity(0.35)),at:CGPoint(x:left+width/2,y:top+height/2))
            }
        }
    }
}
