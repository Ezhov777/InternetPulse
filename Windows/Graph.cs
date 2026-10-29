using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;

namespace InternetPulse;
public sealed class TrafficGraph:FrameworkElement {
    public List<Sample> Samples=[];public double Seconds=60;public double PeakDown,PeakUp;Point? hover;
    public static Brush Mint=new SolidColorBrush(Color.FromRgb(74,240,217)),Purple=new SolidColorBrush(Color.FromRgb(166,140,255));
    public TrafficGraph(){Height=270;MouseMove+=(_,e)=>{hover=e.GetPosition(this);InvalidateVisual();};MouseLeave+=(_,_)=>{hover=null;InvalidateVisual();};}
    void Text(DrawingContext dc,string text,double x,double y,Brush brush,double size=11){dc.DrawText(new FormattedText(text,I18n.Culture,FlowDirection.LeftToRight,new Typeface("Segoe UI"),size,brush,VisualTreeHelper.GetDpi(this).PixelsPerDip),new Point(x,y));}
    protected override void OnRender(DrawingContext dc){base.OnRender(dc);double left=68,right=Math.Max(left+1,ActualWidth-25),top=35,bottom=Height-35,width=right-left,height=bottom-top;var end=Samples.LastOrDefault()?.Time??DateTimeOffset.Now;var start=end.AddSeconds(-Seconds);var visible=Samples.Where(x=>x.Time>=start).ToList();double peak=visible.Select(x=>Math.Max(x.Down,x.Up)).DefaultIfEmpty(0).Max();double raw=Math.Max(1,peak*1.12)/4,power=Math.Pow(10,Math.Floor(Math.Log10(raw))),max=new[]{1d,2,2.5,5,10}.First(x=>x*power>=raw)*power*4;
        Text(dc,I18n.L("Мбит/с"),0,5,Brushes.Gray);
        for(int i=0;i<=4;i++){double y=top+height*i/4;dc.DrawLine(new Pen(new SolidColorBrush(Color.FromArgb(35,255,255,255)),1),new Point(left,y),new Point(right,y));Text(dc,(max*(1-i/4d)).ToString("N0",I18n.Culture),0,y-7,Brushes.Gray);var date=start.AddSeconds(Seconds*i/4);Text(dc,date.LocalDateTime.ToString("HH:mm:ss",I18n.Culture),left+width*i/4-(i==4?48:0),bottom+12,Brushes.Gray,10);}
        Point P(Sample s,bool up)=>new(left+width*(s.Time-start).TotalSeconds/Seconds,top+height*(1-(up?s.Up:s.Down)/max));
        dc.PushClip(new RectangleGeometry(new Rect(left,top,width,height)));
        int step=Math.Max(1,(int)Math.Ceiling(visible.Count/1500d));var points=visible.Where((_,i)=>i%step==0||i==visible.Count-1).ToList();
        foreach(bool up in new[]{false,true}){var brush=up?Purple:Mint;var geometry=new StreamGeometry();using(var g=geometry.Open()){if(points.Count>0){g.BeginFigure(P(points[0],up),false,false);g.PolyLineTo(points.Skip(1).Select(x=>P(x,up)).ToList(),true,false);}}geometry.Freeze();dc.DrawGeometry(null,new Pen(brush,2),geometry);if(points.Count>0)dc.DrawEllipse(brush,null,P(points[^1],up),3,3);}
        dc.Pop();
        if(hover is Point h&&h.X>=left&&h.X<=right&&visible.Count>0){var date=start.AddSeconds((h.X-left)/width*Seconds);var selected=visible.MinBy(x=>Math.Abs((x.Time-date).TotalSeconds))!;double x=P(selected,false).X;dc.DrawLine(new Pen(Brushes.Gray,1),new Point(x,top),new Point(x,bottom));ToolTip=$"{selected.Time.LocalDateTime:HH:mm:ss} · ↓ {I18n.Speed(selected.Down)} · ↑ {I18n.Speed(selected.Up)} {I18n.L("Мбит/с")}";}
        if(visible.Count<2)Text(dc,I18n.L("Здесь появится скорость вашего соединения"),left+20,top+height/2,Brushes.Gray,13);
    }
}
