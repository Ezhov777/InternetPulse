using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;

namespace InternetPulse;
public sealed class NetworkEngine:IDisposable {
    readonly HttpClient http;CancellationTokenSource? cancellation;Task[] tasks=[];
    long downloaded,uploaded;int errors;double latency=-1;string lastError="";readonly object statusLock=new();
    public bool Running=>cancellation!=null;
    public long Downloaded=>Interlocked.Read(ref downloaded);public long Uploaded=>Interlocked.Read(ref uploaded);public int Errors=>Volatile.Read(ref errors);
    public double Latency{get{lock(statusLock)return latency;}} public string LastError{get{lock(statusLock)return lastError;}}
    public NetworkEngine(){http=new(new SocketsHttpHandler{AutomaticDecompression=DecompressionMethods.None,AllowAutoRedirect=true,MaxAutomaticRedirections=3,ConnectTimeout=TimeSpan.FromSeconds(8),MaxConnectionsPerServer=40,PooledConnectionLifetime=TimeSpan.FromMinutes(5),UseCookies=false}){Timeout=Timeout.InfiniteTimeSpan};http.DefaultRequestHeaders.UserAgent.ParseAdd("InternetPulse/1.7.0");http.DefaultRequestHeaders.CacheControl=new(){NoCache=true};http.DefaultRequestHeaders.AcceptEncoding.ParseAdd("identity");}
    public static bool ValidUrl(string value)=>Uri.TryCreate(value,UriKind.Absolute,out var u)&&new[]{"http","https"}.Contains(u.Scheme)&&!string.IsNullOrEmpty(u.Host)&&string.IsNullOrEmpty(u.UserInfo)&&value.Length<2000;
    public void Start(string downUrl,string upUrl,double down,double up,int streams,bool maximum){
        if(Running)throw new InvalidOperationException("Already running");
        if(!double.IsFinite(down)||!double.IsFinite(up)||down<0||up<0||down>20000||up>20000||down+up<=0||!new[]{1,4,8,16}.Contains(streams)||(down>0&&(!ValidUrl(downUrl)||(!maximum&&down<0.1)))||(up>0&&(!ValidUrl(upUrl)||(!maximum&&up<0.1))))throw new ArgumentException("Invalid test parameters");
        downloaded=uploaded=0;errors=0;lock(statusLock){latency=-1;lastError="";}cancellation=new();var token=cancellation.Token;var workers=new List<Task>();
        for(int i=0;i<streams;i++){if(down>0)workers.Add(Worker(downUrl,false,maximum?0:down/streams,token));if(up>0)workers.Add(Worker(upUrl,true,maximum?0:up/streams,token));}
        workers.Add(Probe(down>0?downUrl:upUrl,token));tasks=workers.ToArray();
    }
    async Task Worker(string url,bool upload,double mbps,CancellationToken token){
        var pace=new Pacer(mbps);int failures=0;var buffer=new byte[65536];
        while(!token.IsCancellationRequested){
            try{
                using var request=new HttpRequestMessage(upload?HttpMethod.Put:HttpMethod.Get,url);
                if(upload)request.Content=new GeneratedContent(Math.Clamp(mbps==0?33_554_432:(long)(mbps*125000*20),262144,33_554_432),pace,n=>Interlocked.Add(ref uploaded,n),token);
                using var response=await http.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,token);response.EnsureSuccessStatusCode();
                if(!upload&&response.Content.Headers.ContentType?.MediaType?.Contains("html",StringComparison.OrdinalIgnoreCase)==true)throw new HttpRequestException("Server returned HTML instead of test data");
                await using var input=await response.Content.ReadAsStreamAsync(token);long received=0;
                while(true){using var idle=CancellationTokenSource.CreateLinkedTokenSource(token);idle.CancelAfter(TimeSpan.FromSeconds(20));int n=await input.ReadAsync(buffer,idle.Token);if(n==0)break;if(!upload){Interlocked.Add(ref downloaded,n);received+=n;await pace.Advance(n,token);}}
                if(!upload&&received==0)throw new HttpRequestException("Empty download");failures=0;
            }catch(OperationCanceledException)when(token.IsCancellationRequested){break;}
            catch(Exception ex)when(ex is HttpRequestException or IOException or OperationCanceledException){Interlocked.Increment(ref errors);failures++;int delay=failures<5?1<<failures:30;lock(statusLock)lastError=$"{(upload?"Upload":"Download")}: {ex.Message} · retry {delay}s";try{await Task.Delay(TimeSpan.FromSeconds(delay),token);}catch(OperationCanceledException){break;}pace.Reset();}
        }
    }
    async Task Probe(string url,CancellationToken token){while(!token.IsCancellationRequested){try{using var timeout=CancellationTokenSource.CreateLinkedTokenSource(token);timeout.CancelAfter(TimeSpan.FromSeconds(5));using var request=new HttpRequestMessage(HttpMethod.Head,url);var watch=Stopwatch.StartNew();using var response=await http.SendAsync(request,HttpCompletionOption.ResponseHeadersRead,timeout.Token);lock(statusLock)latency=response.IsSuccessStatusCode?watch.Elapsed.TotalMilliseconds:-1;await Task.Delay(2000,token);}catch(OperationCanceledException)when(token.IsCancellationRequested){break;}catch(Exception ex)when(ex is HttpRequestException or OperationCanceledException or IOException){lock(statusLock)latency=-1;try{await Task.Delay(3000,token);}catch(OperationCanceledException){break;}}}}
    public async Task Stop(){var active=cancellation;if(active==null)return;active.Cancel();await Task.WhenAll(tasks);if(cancellation==active){cancellation=null;active.Dispose();tasks=[];}}
    public void Dispose(){cancellation?.Cancel();http.Dispose();}
    sealed class GeneratedContent:HttpContent {
        readonly long length;readonly Pacer pace;readonly Action<int> count;readonly CancellationToken token;readonly byte[] bytes=RandomNumberGenerator.GetBytes(65536);
        public GeneratedContent(long length,Pacer pace,Action<int> count,CancellationToken token){this.length=length;this.pace=pace;this.count=count;this.token=token;Headers.ContentType=new MediaTypeHeaderValue("application/octet-stream");Headers.ContentLength=length;}
        protected override bool TryComputeLength(out long result){result=length;return true;}
        protected override Task SerializeToStreamAsync(Stream stream,TransportContext? context)=>Write(stream);
        async Task Write(Stream output){for(long sent=0;sent<length;){int n=(int)Math.Min(bytes.Length,length-sent);await pace.Advance(n,token);await output.WriteAsync(bytes.AsMemory(0,n),token);count(n);sent+=n;}}
    }
    sealed class Pacer(double mbps){readonly Stopwatch watch=Stopwatch.StartNew();long count;public void Reset(){watch.Restart();count=0;}public async ValueTask Advance(int bytes,CancellationToken token){if(mbps<=0)return;count+=bytes;double delay=count/(mbps*125000)-watch.Elapsed.TotalSeconds;if(delay>0.001)await Task.Delay(TimeSpan.FromSeconds(delay),token);}}
}
