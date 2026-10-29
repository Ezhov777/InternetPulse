global using System.IO;
global using System.Net.Http;
using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace InternetPulse;
public static class I18n {
    public static readonly (string Code,string Name)[] Languages=[("ru","Русский"),("en","English"),("fr","Français"),("de","Deutsch"),("es","Español")];
    public static string Code=Languages.Any(x=>x.Code==CultureInfo.CurrentUICulture.TwoLetterISOLanguageName)?CultureInfo.CurrentUICulture.TwoLetterISOLanguageName:"en";
    public static CultureInfo Culture=>CultureInfo.GetCultureInfo(new Dictionary<string,string>{{"ru","ru-RU"},{"en","en-GB"},{"fr","fr-FR"},{"de","de-DE"},{"es","es-ES"}}[Code]);
    static readonly Dictionary<string,Dictionary<string,string>> Words=JsonSerializer.Deserialize<Dictionary<string,Dictionary<string,string>>>(File.ReadAllText(Path.Combine(AppContext.BaseDirectory,"Resources","Translations.json")))!;
    public static string L(string key,params string[] args){var text=Words.GetValueOrDefault(Code)?.GetValueOrDefault(key)??key;for(int i=0;i<args.Length;i++)text=text.Replace("{"+i+"}",args[i]);return text;}
    public static string Amount(long bytes,string unit)=>((double)bytes/(unit=="TB"?1e12:unit=="GB"?1e9:1e6)).ToString("N2",Culture)+" "+L(unit);
    public static string Bytes(long bytes)=>Amount(bytes,bytes>=1_000_000_000_000?"TB":bytes>=1_000_000_000?"GB":"MB");
    public static string Speed(double speed)=>speed.ToString("N1",Culture);
}
public record Server(string id,string name,string location,string country,string download,string? upload,string source){public string Label=>$"{country} · {name} · {I18n.L(location)} · {I18n.L(upload==null?"↓ скачивание":"↓↑ оба направления")}";}
public record ReleaseEntry(string version,string date,string title,string[] changes);
public record Sample(DateTimeOffset Time,double Down,double Up,long Downloaded,long Uploaded,double Latency,int Errors);
public class DayTraffic {public string Day{get;set;}="";public long Downloaded{get;set;}public long Uploaded{get;set;}}
public sealed class Settings {
    public string Language{get;set;}=I18n.Code;public string Unit{get;set;}="MB";public double DownLimit{get;set;}=10;public double UpLimit{get;set;}=5;
    public int Streams{get;set;}=4;public int Duration{get;set;}=15;public bool Maximum{get;set;}=false;public bool DownloadEnabled{get;set;}=true;public bool UploadEnabled{get;set;}=true;
    public string DownloadUrl{get;set;}="http://speedtest.rastrnet.ru/1GB.zip";public string UploadUrl{get;set;}="http://speedtest.rastrnet.ru/speedtest/upload.php";
    public List<DayTraffic> History{get;set;}=[];
}
public sealed class Store {
    readonly string path;public Settings Value{get;private set;}=new();
    public Store(string? directory=null){directory??=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"InternetPulse");Directory.CreateDirectory(directory);path=Path.Combine(directory,"settings.json");try{if(File.Exists(path))Value=JsonSerializer.Deserialize<Settings>(File.ReadAllText(path))??new();}catch(JsonException){}catch(IOException){}
        if(!I18n.Languages.Any(x=>x.Code==Value.Language))Value.Language="en";if(!new[]{"MB","GB","TB"}.Contains(Value.Unit))Value.Unit="MB";if(!new[]{1,4,8,16}.Contains(Value.Streams))Value.Streams=4;
    }
    public void Record(long down,long up,DateTimeOffset now){if(down<0||up<0)throw new ArgumentOutOfRangeException();if(down+up==0)return;var key=now.LocalDateTime.ToString("yyyy-MM-dd",CultureInfo.InvariantCulture);var day=Value.History.FirstOrDefault(x=>x.Day==key);if(day==null){day=new(){Day=key};Value.History.Add(day);}day.Downloaded+=down;day.Uploaded+=up;}
    public void Save(){var temporary=path+".tmp";File.WriteAllText(temporary,JsonSerializer.Serialize(Value,new JsonSerializerOptions{WriteIndented=true}));File.Move(temporary,path,true);}
}
