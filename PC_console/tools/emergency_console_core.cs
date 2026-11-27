using System;
using System.Drawing;
using System.Drawing.Text;
using System.Drawing.Drawing2D;
public sealed class CaptionImage {
 public int Width; public byte[] Data; public Bitmap Preview; public string Font;
}
public static class SubtitleCodec {
 public static ushort Crc(byte[] data,int count) {
  int c=65535;for(int i=0;i<count;i++){c^=data[i]<<8;for(int k=0;k<8;k++)c=((c&32768)!=0?((c<<1)^0x1021):(c<<1))&65535;}return (ushort)c;
 }
 public static byte[] Packet(byte op,byte id,int index,ushort digest,byte[] data) {
  byte[] p=new byte[28];p[0]=18;p[1]=1;p[2]=op;p[3]=id;p[4]=(byte)index;p[5]=(byte)(index>>8);p[6]=(byte)digest;p[7]=(byte)(digest>>8);
  if(data!=null)Array.Copy(data,0,p,8,16);p[24]=0x31;p[25]=0x42;p[26]=0x55;p[27]=0x53;return p;
 }
 public static byte[] Frame(byte[] p) {
  byte[] f=new byte[33];f[0]=27;f[1]=83;f[2]=1;Array.Copy(p,0,f,3,28);ushort c=Crc(p,28);f[31]=(byte)c;f[32]=(byte)(c>>8);return f;
 }
 public static void CheckReply(byte[] r,byte[] p) {
  if(r.Length!=10||r[0]!=27||r[1]!=65||r[2]!=1||r[3]!=p[3]||r[4]!=p[2]||r[5]!=p[4]||r[6]!=p[5]||Crc(r,8)!=(r[8]|r[9]<<8))throw new Exception("Invalid subtitle reply. Check matching A/B firmware and exclusive COM access.");
  if(r[7]!=0)throw new Exception("Subtitle rejected, status="+r[7]+". Please visually verify the last committed subtitle. 2=UART CRC,3=offline,4=busy,5=network timeout,6=format,10=width,11=order,13=digest.");
 }
 public static CaptionImage Raster(string text) {
  if(String.IsNullOrWhiteSpace(text))throw new Exception("Please enter a non-empty single-line message, or use Clear.");
  if(text.IndexOf('\r')>=0||text.IndexOf('\n')>=0)throw new Exception("Only one line is supported.");
  if(text.Length>256)throw new Exception("Message too long.");
  for(int size=16;size>=10;size--)using(Font font=new Font("Microsoft YaHei",size,FontStyle.Regular,GraphicsUnit.Pixel))using(Bitmap temp=new Bitmap(1400,64)) {
   using(Graphics g=Graphics.FromImage(temp)) {
    g.Clear(Color.Black);g.TextRenderingHint=TextRenderingHint.SingleBitPerPixelGridFit;g.SmoothingMode=SmoothingMode.None;
    if(g.MeasureString(text,font,1400,StringFormat.GenericTypographic).Width>1100)throw new Exception("Message too wide. Maximum 1024 font pixels, roughly 64 Chinese characters.");
    g.DrawString(text,font,Brushes.White,new PointF(0,0),StringFormat.GenericTypographic);
   }
   int left=1400,right=-1,top=64,bottom=-1;
   for(int y=0;y<64;y++)for(int x=0;x<1400;x++)if(temp.GetPixel(x,y).R>127){left=Math.Min(left,x);right=Math.Max(right,x);top=Math.Min(top,y);bottom=Math.Max(bottom,y);}
   if(right<left)throw new Exception("The selected font produced no visible glyphs.");
   if(bottom-top+1>16)continue;
   int width=((right-left+1+15)/16)*16;if(width>1024)throw new Exception("Message too wide. Maximum 1024 font pixels; shorten it.");
   byte[] data=new byte[2048];Bitmap preview=new Bitmap(width*2,32);int offset=(16-(bottom-top+1))/2;
   using(Graphics g=Graphics.FromImage(preview))g.Clear(Color.FromArgb(0x12,0x38,0x5a));
   for(int y=0;y<16;y++)for(int x=0;x<1024;x++) {
    int sy=y-offset+top;bool on=x<=right-left&&sy>=top&&sy<=bottom&&temp.GetPixel(x+left,sy).R>127;
    if(on){int word=y*64+x/16;int bit=15-x%16;data[word*2+bit/8]|=(byte)(1<<(bit%8));if(x<width)for(int yy=0;yy<2;yy++)for(int xx=0;xx<2;xx++)preview.SetPixel(x*2+xx,y*2+yy,Color.White);}
   }
   return new CaptionImage{Width=width,Data=data,Preview=preview,Font=font.FontFamily.Name+" "+size+"px"};
  }
  throw new Exception("Could not fit font height into16 pixels.");
 }
}
namespace EmergencyConsole {
 public interface ITransport : System.IDisposable {
  void Open(); void Close(); bool IsOpen {get;} void Write(byte[] data,int offset,int count); int Read(byte[] data,int offset,int count);
 }
 public sealed class SerialTransport : ITransport {
  readonly System.IO.Ports.SerialPort port;
  public SerialTransport(string name){port=new System.IO.Ports.SerialPort(name,115200,System.IO.Ports.Parity.None,8,System.IO.Ports.StopBits.One);port.Handshake=System.IO.Ports.Handshake.None;port.DtrEnable=false;port.RtsEnable=false;port.ReadTimeout=100;port.WriteTimeout=3000;}
  public bool IsOpen {get{return port.IsOpen;}}
  public void Open(){port.Open();port.DiscardInBuffer();} public void Close(){port.Close();} public void Dispose(){port.Dispose();}
  public void Write(byte[] a,int o,int n){port.Write(a,o,n);}public int Read(byte[] a,int o,int n){return port.Read(a,o,n);}
 }
 public sealed class BoardStatus {
  public uint Ms,Req,Act,Bar,Apply,Ack,Src,Link,Phy,Cache,Fault,Fresh,Age,Exit,Closed,Route,Rev,Log,Lost,RxErr;
  public string Raw;public long ReceivedTicks;
  public string Sensor="NONE";public short TempRaw;public uint TempValid,TempWarn,TempAlarm,TempClearAllowed,TempFault;
  public bool SensorInstalled {get{return Sensor=="DS18B20";}}
  public string SensorSignature {get{return Sensor+"/"+TempRaw+"/"+TempValid+"/"+TempWarn+"/"+TempAlarm+"/"+TempClearAllowed+"/"+TempFault;}}
  public bool Emergency {get{return (Act&1)!=0;}}
  public bool RouteQualified {get{return Link==1&&Emergency&&Req==Act&&Ack==1&&Fresh==1&&Age<1000&&Apply==1;}}
  static uint Hex(System.Collections.Generic.Dictionary<string,string> f,string k){string s;if(!f.TryGetValue(k,out s))throw new System.FormatException("状态缺少字段："+k);if(s.StartsWith("0x"))s=s.Substring(2);uint v;if(s.Length<1||s.Length>8||!uint.TryParse(s,System.Globalization.NumberStyles.AllowHexSpecifier,System.Globalization.CultureInfo.InvariantCulture,out v))throw new System.FormatException("非法状态字段："+k);return v;}
  public static BoardStatus Parse(string line){
   var f=new System.Collections.Generic.Dictionary<string,string>(System.StringComparer.Ordinal);
   foreach(string part in line.Split(new char[]{' '},System.StringSplitOptions.RemoveEmptyEntries)){int p=part.IndexOf('=');if(p<1||p==part.Length-1||f.ContainsKey(part.Substring(0,p)))throw new System.FormatException("状态格式或重复字段错误");f.Add(part.Substring(0,p),part.Substring(p+1));}
   string sensor;if(!f.TryGetValue("SENSOR",out sensor)||(sensor!="NONE"&&sensor!="DS18B20"))throw new System.FormatException("不兼容的传感器状态");
   var s=new BoardStatus();s.Ms=Hex(f,"MS");s.Req=Hex(f,"REQ");s.Act=Hex(f,"ACT");s.Bar=Hex(f,"BAR");s.Apply=Hex(f,"APPLY");s.Ack=Hex(f,"ACK");s.Src=Hex(f,"SRC");s.Link=Hex(f,"LINK");s.Phy=Hex(f,"PHY");s.Cache=Hex(f,"CACHE");s.Fault=Hex(f,"FAULT");s.Fresh=Hex(f,"FRESH");s.Age=Hex(f,"AGE");s.Exit=Hex(f,"EXIT");s.Closed=Hex(f,"CLOSED");s.Route=Hex(f,"ROUTE");s.Rev=Hex(f,"REV");s.Log=Hex(f,"LOG");s.Lost=Hex(f,"LOST");s.RxErr=Hex(f,"RXERR");
   if(s.Req>7||s.Act>7||s.Bar>3||s.Apply>1||s.Ack>1||s.Src>(sensor=="DS18B20"?2u:1u)||s.Link>1||s.Phy>1||s.Fresh>1||s.Exit>4||s.Cache>255||s.Fault>15||s.Closed>65535||s.Route>65535||s.Rev>65535||s.Log>64||s.Lost>65535||s.RxErr>65535)throw new System.FormatException("状态字段越界");
   s.Sensor=sensor;
   if(s.SensorInstalled){uint raw=Hex(f,"TRAW");if(raw>65535)throw new System.FormatException("温度原始值越界");s.TempRaw=unchecked((short)raw);s.TempValid=Hex(f,"TV");s.TempWarn=Hex(f,"TW");s.TempAlarm=Hex(f,"TA");s.TempClearAllowed=Hex(f,"TC");s.TempFault=Hex(f,"TF");
    if(s.TempValid>1||s.TempWarn>1||s.TempAlarm>1||s.TempClearAllowed>1||s.TempFault>7)throw new System.FormatException("温度状态字段越界");
    if(s.TempValid==1&&(s.TempFault!=0||s.TempRaw < -880||s.TempRaw>2000))throw new System.FormatException("有效温度与故障或量程矛盾");
    if(s.TempAlarm==1&&s.TempWarn!=1)throw new System.FormatException("锁存告警缺少预警标志");
    if(s.TempClearAllowed==1&&(s.TempAlarm!=1||s.TempValid!=1||s.TempRaw>800))throw new System.FormatException("温度解除资格矛盾");
   }
   s.Raw=line;s.ReceivedTicks=System.Diagnostics.Stopwatch.GetTimestamp();return s;
  }
  public string Signature {get{return Req+"/"+Act+"/"+Bar+"/"+Apply+"/"+Ack+"/"+Link+"/"+Fresh+"/"+Exit+"/"+Closed+"/"+Route+"/"+Rev+"/"+Cache+"/"+Fault;}}
 }
 public static class Policy {
  public static string SensorFaultName(uint n){switch(n){case 0:return "无通信错误";case 1:return "未检出探头";case 2:return "DQ总线异常";case 3:return "CRC校验失败";case 4:return "配置或量程错误";case 5:return "转换未完成";case 6:return "内部状态恢复";default:return "尚无新鲜有效读数";}}
  public static string TemperatureText(BoardStatus s){if(s==null)return "等待串口温度状态";if(!s.SensorInstalled)return "当前固件未配置温度传感器";string value=s.TempValid==1?(s.TempRaw/16.0).ToString("F4",System.Globalization.CultureInfo.InvariantCulture)+" ℃":"温度未知 · "+SensorFaultName(s.TempFault);return value+"\r\n"+(s.TempAlarm==1?(s.TempClearAllowed==1?"高温已锁存 · 已满足人工解除条件":"高温已锁存 · 保持应急"):s.TempWarn==1?"温度预警":"未锁存温度告警");}
  public static string SourceName(uint n){return n==2?"温度自动触发":n==1?"串口请求":"板载按键/既有控制";}
  public static string EventName(uint state){if((state&1)==0)return "正常轮播";switch(state){case 1:return "火灾应急";case 3:return "地震应急";case 5:return "实验室事故";case 7:return "应急演练";default:return "未知事件";}}
  public static string ExitName(uint n){switch(n){case 1:return "1号北出口";case 2:return "2号西出口";case 3:return "3号东出口";case 4:return "4号南出口";default:return "未返回可用出口";}}
  public static string BarrierName(uint n){switch(n){case 0:return "无附加封路";case 1:return "增加一处封路";case 2:return "增加两处封路";case 3:return "四出口关闭预案";default:return "未知";}}
  public static string RouteText(BoardStatus s){if(s==null)return "尚未收到板端状态";if(s.Link!=1)return "双板离线，历史路线失效";if(!s.Emergency)return s.Req==s.Act?"正常轮播，无疏散路线":"应急请求等待板端确认";if(s.Req!=s.Act||s.Ack!=1)return "实际事件与请求未确认，暂不推荐出口（本地告警可能仍保留）";if(s.Fresh!=1||s.Age>=1000)return "路线数据过期或尚未收到，等待更新";if(s.Apply!=1)return "封路预案尚未吻合，等待路线更新";if(s.Exit==0&&s.Route==0)return "未返回可用疏散路线，请等待现场指引";if(s.Exit==0||s.Route==0)return "出口与路线信息不完整，等待更新";return "推荐"+ExitName(s.Exit)+"；已收到当前封路预案对应路线";}
  public static string Caption(BoardStatus s){
   if(s==null||s.Link!=1)return null;
   if(s.SensorInstalled&&s.TempAlarm==1&&!s.Emergency)return "高温报警｜火灾预案确认中，请听从现场指引。";
   if(!s.Emergency)return s.SensorInstalled&&s.TempValid==1&&s.TempWarn==1?"温度预警｜已达45℃，请检查现场。":null;
   string title=s.SensorInstalled&&s.Src==2&&s.Act==1?"高温触发火灾｜":EventName(s.Act)+"｜";
   if(!s.RouteQualified)return title+"路线更新中，请听从现场指引。";
   if(s.Exit==0&&s.Route==0)return title+"暂无可用路线，请听从现场指引。";if(s.Exit==0||s.Route==0)return title+"路线更新中，请听从现场指引。";
   return title+"推荐"+ExitName(s.Exit)+"，请沿绿色路线疏散。";
  }
  public static string ErrorText(string line){switch(line){case "ERR LINK_OFFLINE":return "双板未联机，请求被拒绝";case "ERR KEY_PRIORITY":return "板载按键优先，本次请求被拒绝";case "ERR NOT_EMERGENCY":return "当前不是应急状态，不能设置路障";case "ERR BUSY":return "板端忙，本次请求未执行";case "ERR SENSOR_LOCK":return "温度告警已锁存，需先降温并人工解除；路障控制仍可用";case "ERR SENSOR_COOL":return "尚未连续3次降至50℃或以下，或探头状态无效，不能解除";default:return "板端拒绝："+line;}}
 }
 public sealed class Notice {public string Kind,Text;public int Value;public Notice(string k,string t,int v){Kind=k;Text=t;Value=v;}}
 public sealed class AuditRecord {public string ReceivedAt,Elapsed,Kind,Text,Raw;}
 public sealed class BoardRecord {public string ReceivedAt,Ms,Type,Context,Data,Description,Raw;}
 public sealed class View {
  public bool Connected,Healthy,Auto,Busy,Running,RequestPending;public BoardStatus Status;public string Action,Operation,Drill,AutoCaption,LastError,FailureKind;public int Progress,AuditLost;public long BoardLogRevision;public int BoardLogCount;
 }
 internal sealed class Job {public string Kind,Text;}
 public sealed class Session : System.IDisposable {
  readonly ITransport io;readonly int pollMs,autoMinMs;readonly object gate=new object();
  readonly System.Collections.Generic.List<Job> jobs=new System.Collections.Generic.List<Job>();
  readonly System.Collections.Generic.Queue<Notice> notices=new System.Collections.Generic.Queue<Notice>();
  readonly System.Collections.Generic.List<AuditRecord> audit=new System.Collections.Generic.List<AuditRecord>();
  System.Collections.Generic.List<BoardRecord> boardLog=new System.Collections.Generic.List<BoardRecord>();
  readonly System.Diagnostics.Stopwatch clock=new System.Diagnostics.Stopwatch();
  System.Threading.Thread thread;volatile bool stop;bool connected,auto=true,busy,systemOwned,systemOwnedNonEmergency;BoardStatus status;
  string lastError="",failureKind="";
  string action="尚未连接",operation="等待连接",lastAuto,lastSignature,lastSensorSignature,pending;int expectedState=-1,expectedBar=-1,progress,auditLost;long nextPoll,lastPublish,logRevision,drillStart=-1,drillDuration;string drillState="未开始";byte tag;
  public Session(ITransport transport):this(transport,800,1200){}
  public Session(ITransport transport,int pollingMs,int autoPublishMs){io=transport;pollMs=pollingMs;autoMinMs=autoPublishMs;tag=(byte)new System.Random().Next(1,256);}
  static bool Recent(BoardStatus s){return s!=null&&(System.Diagnostics.Stopwatch.GetTimestamp()-s.ReceivedTicks)/(double)System.Diagnostics.Stopwatch.Frequency<2.5;}
  public View ReadView(){lock(gate){var v=new View();v.LastError=lastError;v.FailureKind=failureKind;v.Connected=connected;v.Running=thread!=null&&thread.IsAlive;v.Healthy=connected&&Recent(status);v.Status=status;v.RequestPending=pending!=null;v.AutoCaption=CaptionFor(status,pending!=null);v.Auto=auto;v.Busy=busy;v.Action=action;v.Operation=operation;v.Progress=progress;v.AuditLost=auditLost;v.BoardLogRevision=logRevision;v.BoardLogCount=boardLog.Count;v.Drill=drillState+" "+System.TimeSpan.FromMilliseconds(drillStart>=0?clock.ElapsedMilliseconds-drillStart:drillDuration).ToString(@"hh\:mm\:ss");return v;}}
  void Add(string kind,string text,string raw){lock(gate){if(audit.Count==4096){audit.RemoveAt(0);auditLost++;}audit.Add(new AuditRecord{ReceivedAt=System.DateTimeOffset.Now.ToString("o"),Elapsed=clock.ElapsedMilliseconds.ToString(),Kind=kind,Text=text,Raw=raw??""});if(notices.Count==512)notices.Dequeue();notices.Enqueue(new Notice(kind,text,0));}}
  void Progress(int n){lock(gate){progress=n;}}
  public Notice[] DrainNotices(){lock(gate){var a=notices.ToArray();notices.Clear();return a;}}
  public void Start(){lock(gate){if(thread!=null)throw new System.InvalidOperationException("此会话已启动");clock.Start();thread=new System.Threading.Thread(Run);thread.IsBackground=true;thread.Name="FPGA console serial owner";thread.Start();}}
  public void Stop(){stop=true;lock(gate){jobs.Clear();}}
  public void Dispose(){Stop();if(thread!=null)thread.Join(4500);}
  public void InheritAudit(Session previous){
   if(previous==null || previous==this)return;
   AuditRecord[] rows;int lost;lock(previous.gate){if(previous.thread!=null&&previous.thread.IsAlive)throw new InvalidOperationException("旧串口会话仍在退出");rows=previous.audit.ToArray();lost=previous.auditLost;}
   lock(gate){if(thread!=null)throw new InvalidOperationException("须在启动新会话前继承审计");audit.AddRange(rows);auditLost=lost;}
  }
  public void SetAutomatic(bool value){lock(gate){auto=value;if(value)lastAuto=null;}Add("设置",value?"已开启状态联动字幕":"已关闭自动联动；已提交字幕需手动清除或替换",null);}
  bool Enqueue(string kind,string text){lock(gate){if(!connected||stop)throw new System.InvalidOperationException("请先连接并收到有效板端状态");if(jobs.Count>=16)throw new System.InvalidOperationException("操作队列已满，请等待");if(kind=="MANUAL")jobs.RemoveAll(delegate(Job j){return j.Kind=="MANUAL";});jobs.Add(new Job{Kind=kind,Text=text});return true;}}
  public bool Request(string command){if(!System.Text.RegularExpressions.Regex.IsMatch(command,@"\A(?:DEMO (?:FIRE|QUAKE|LAB|DRILL|STOP)|BARRIER SET [0-3])\z"))throw new System.ArgumentException("不支持的控制命令");return Enqueue("CONTROL",command);}
  public bool Publish(string text){if(System.String.IsNullOrWhiteSpace(text))throw new System.ArgumentException("请输入字幕正文");if(text.IndexOf('\n')>=0||text.IndexOf('\r')>=0||text.Length>256)throw new System.ArgumentException("字幕必须为单行且不超过256字符");return Enqueue("MANUAL",text);}
  public bool ClearTemperatureAlarm(){return Enqueue("TEMPCLEAR","TEMP CLEAR");}
  public bool Clear(){return Enqueue("CLEAR",null);}public bool ReadLog(){return Enqueue("LOG",null);}public bool ClearLog(){return Enqueue("LOGCLEAR",null);}
  Job TakeControl(){lock(gate){int n=jobs.FindIndex(delegate(Job j){return j.Kind=="CONTROL"||j.Kind=="TEMPCLEAR";});if(n<0)return null;Job r=jobs[n];jobs.RemoveAt(n);return r;}}
  Job Take(){lock(gate){if(jobs.Count==0)return null;Job r=jobs[0];jobs.RemoveAt(0);return r;}}
  byte NextTag(){tag=(byte)(tag==255?1:tag+1);return tag;}
  void CheckStop(){if(stop)throw new System.OperationCanceledException();}
  byte ReadByte(long deadline){byte[] b=new byte[1];while(clock.ElapsedMilliseconds<deadline){CheckStop();try{int n=io.Read(b,0,1);if(n==1)return b[0];if(n==0)System.Threading.Thread.Sleep(1);}catch(System.TimeoutException){}}throw new System.TimeoutException("串口等待超时；不自动重发控制命令。字幕可能已提交但确认丢失，请目视核对。");}
  string Line(long deadline){var s=new System.Text.StringBuilder();while(true){byte b=ReadByte(deadline);if(b==10){if(s.Length==0)continue;return s.ToString();}if(b==13)continue;if(b<32||b>126||s.Length>=1024)throw new System.FormatException("收到不匹配的串口响应，请关闭其他串口工具并核对配套固件");s.Append((char)b);}}
  void WriteLine(string text){CheckStop();byte[] b=System.Text.Encoding.ASCII.GetBytes(text+"\r\n");io.Write(b,0,b.Length);}
  string Command(string command){WriteLine(command);return Line(clock.ElapsedMilliseconds+4000);}
  void Packet(byte[] p){CheckStop();byte[] f=SubtitleCodec.Frame(p);io.Write(f,0,f.Length);byte[] r=new byte[10];long deadline=clock.ElapsedMilliseconds+3500;for(int n=0;n<10;n++)r[n]=ReadByte(deadline);SubtitleCodec.CheckReply(r,p);}
  // The caller transfers ownership of an already validated image. Automatic
  // captions are rendered here; a clear transaction never renders any image.
  void Upload(string text,bool clear,CaptionImage prepared=null){
   CaptionImage image=prepared;
   lock(gate){busy=true;operation=clear?"清除字幕，等待A板VS提交确认":"发送字模，旧字幕保持；等待A板VS提交确认";progress=0;}
   byte id=NextTag();
   try{
    if(clear){Packet(SubtitleCodec.Packet(3,id,0,0,null));return;}
    if(image==null)image=SubtitleCodec.Raster(text);
    ushort digest=SubtitleCodec.Crc(image.Data,2048);
    Packet(SubtitleCodec.Packet(0,id,image.Width,0,null));
    for(int n=0;n<128;n++){
     byte[] block=new byte[16];
     System.Array.Copy(image.Data,n*16,block,0,16);
     Packet(SubtitleCodec.Packet(1,id,n,0,block));
     Progress(n+1);
    }
    Packet(SubtitleCodec.Packet(2,id,128,digest,null));
   }finally{
    try{if(image!=null)image.Preview.Dispose();}
    finally{lock(gate){busy=false;}}
   }
  }
  bool IsManualBlocked(){lock(gate){return auto&&status!=null&&(status.Emergency||status.SensorInstalled&&(status.TempAlarm==1||status.TempWarn==1));}}
  void Control(Job j){
   lock(gate){if(!Recent(status)||status.Link!=1){action="拒绝发送：状态过期或双板离线";Add("拒绝",action,j.Text);return;}busy=true;operation="请求："+j.Text;}
   string answer;try{answer=Command(j.Text);}finally{lock(gate){busy=false;}}
   string expected=j.Text.StartsWith("BARRIER SET ")?"OK REQUEST BARRIER="+j.Text.Substring(12):"OK REQUEST STATE="+StateFor(j.Text);
   if(answer.StartsWith("ERR ")){lock(gate){action=Policy.ErrorText(answer);}Add("拒绝",Policy.ErrorText(answer),answer);return;}
   if(answer!=expected)throw new System.FormatException("控制回包与请求不匹配："+answer);
   lock(gate){if(pending!=null)Add("请求替代",pending+"尚未确认，被新请求替代",null);pending=j.Text;expectedBar=j.Text.StartsWith("BARRIER SET ")?int.Parse(j.Text.Substring(12)):-1;expectedState=expectedBar<0?StateFor(j.Text):-1;action="B板已接受请求，等待实际状态/封路确认";}
   Add("请求已接受",j.Text+"；尚未证明A板应用",answer);Poll();
  }
  static int StateFor(string c){switch(c){case "DEMO FIRE":return 1;case "DEMO QUAKE":return 3;case "DEMO LAB":return 5;case "DEMO DRILL":return 7;case "DEMO STOP":return 0;default:throw new System.ArgumentException("非法事件请求");}}
  void EndDrill(string reason){if(drillStart>=0){drillDuration=clock.ElapsedMilliseconds-drillStart;drillStart=-1;drillState=reason;Add("演练观察计时",reason+"；这是电脑观察时长，不是人员疏散完成时间",null);}}
  void Poll(){
   string line=Command("STATUS?");if(line=="ERR BUSY"){Add("状态等待","板端忙，稍后重新查询",line);nextPoll=clock.ElapsedMilliseconds+pollMs;return;}
   BoardStatus s=BoardStatus.Parse(line);
   lock(gate){
    if(status!=null&&s.Ms<status.Ms&&(status.Ms-s.Ms)<0x80000000u){EndDrill("板端重启，计时中断");lastAuto=null;lastSignature=null;lastSensorSignature=null;systemOwned=false;systemOwnedNonEmergency=false;pending=null;action="检测到板端计时复位，需重新确认状态";Add("板端重启","旧请求与字幕所有权记录失效；A复位须重新发送字幕",line);}
    status=s;
    if(s.SensorInstalled&&s.SensorSignature!=lastSensorSignature){lastSensorSignature=s.SensorSignature;Add("温度状态",Policy.TemperatureText(s).Replace("\r\n","；")+"；来源："+Policy.SourceName(s.Src),line);}
    if(s.Signature!=lastSignature){lastSignature=s.Signature;Add("板端状态",Policy.EventName(s.Act)+"；"+Policy.RouteText(s),line);}
    if(s.Link!=1){EndDrill("断链，计时中断");action="双板离线，历史路线不可用";}
    else if(pending!=null){bool ok=expectedBar>=0?s.Bar==expectedBar&&s.RouteQualified:s.Req==expectedState&&s.Act==expectedState&&s.Ack==1&&(!s.Emergency||s.Apply==1&&s.Fresh==1&&s.Age<1000);if(ok){action="板端状态已吻合；HDMI画面以现场为准";Add("板端已应用",pending+"；非HDMI完成确认",line);pending=null;}else action="请求待确认：REQ="+s.Req+" ACT="+s.Act+" ACK="+s.Ack+" APPLY="+s.Apply+"；本地告警可能仍保留";}
    if(s.Link==1&&pending==null){action=s.Req!=s.Act||s.Ack!=1?"当前请求与实际状态未确认（可能为本地告警）":!s.Emergency?"正常状态已回报":s.RouteQualified?"板端事件/封路状态已吻合；非HDMI确认":"事件已回报，路线/封路待更新";}
    if(s.Link==1&&s.Act==7){if(drillStart<0){drillStart=clock.ElapsedMilliseconds;drillDuration=0;drillState="演练观察中";Add("演练观察计时","收到演练实际状态，开始电脑观察计时",line);}}
    else if(s.Link==1)EndDrill("观察结束");
   }
   nextPoll=clock.ElapsedMilliseconds+pollMs;
  }
  static string CaptionFor(BoardStatus s,bool requestPending){return requestPending&&s!=null&&s.Link==1&&s.Emergency?Policy.EventName(s.Act)+"：路线更新中，请听从现场指引。":Policy.Caption(s);}
  void AutoPublish(){
   BoardStatus s;bool enabled,requestPending;lock(gate){s=status;enabled=auto;requestPending=pending!=null;}
   if(!enabled||!Recent(s)||s.Link!=1)return;
   string text=CaptionFor(s,requestPending);bool clear=text==null&&systemOwned&&!s.Emergency&&s.Req==s.Act&&(s.Ack==1||systemOwnedNonEmergency);
   if(text==null&&!clear)return;if(text==lastAuto&&!clear)return;
   if(clock.ElapsedMilliseconds-lastPublish<autoMinMs)return;
   Upload(text,clear);lastPublish=clock.ElapsedMilliseconds;
   lock(gate){lastAuto=text;systemOwned=!clear;systemOwnedNonEmergency=!clear&&!s.Emergency;operation=clear?"正常状态已确认，联动字幕已清除":"联动字幕已收到A板VS提交确认（非HDMI实测）";}
   Add("联动字幕",clear?"撤警实际状态确认，恢复原字幕":text,null);Poll();
  }
  static string DescribeType(uint n){switch(n){case 1:return "启动";case 2:return "双板在线";case 3:return "双板离线";case 4:return "缓存/源故障变化";case 0x10:return "事件请求";case 0x11:return "退出请求";case 0x12:return "路障请求";case 0x13:return "温度自动火灾请求";case 0x70:return "温度/探头状态变化（CTX为温度标志，DATA为有符号1/16℃）";case 0x20:return "实际状态变化";case 0x40:return "场景失效";case 0x50:return "命令拒绝";case 0x60:return "串口帧错";default:return n>=0x30&&n<=0x34?"路线签名变化，出口"+(n-0x30):"未知记录";}}
  void ReadBoardLog(){
   WriteLine("LOG READ 64");long until=clock.ElapsedMilliseconds+6000;string first=Line(until);
   if(first.StartsWith("ERR ")){Add("日志拒绝",Policy.ErrorText(first),first);return;}
   var m=System.Text.RegularExpressions.Regex.Match(first,@"\ALOG COUNT=([0-9A-F]{2})\z");if(!m.Success)throw new System.FormatException("日志头格式不匹配");int count=System.Convert.ToInt32(m.Groups[1].Value,16);if(count>64)throw new System.FormatException("日志条数越界");
   var rows=new System.Collections.Generic.List<BoardRecord>();string at=System.DateTimeOffset.Now.ToString("o");
   for(int n=0;n<count;n++){string raw=Line(until);var row=System.Text.RegularExpressions.Regex.Match(raw,@"\AMS=0x([0-9A-F]{8}) TYPE=([0-9A-F]{2}) CTX=([0-9A-F]{2}) DATA=([0-9A-F]{4})\z");if(!row.Success)throw new System.FormatException("日志行格式不匹配");rows.Add(new BoardRecord{ReceivedAt=at,Ms=System.Convert.ToUInt32(row.Groups[1].Value,16).ToString(),Type=row.Groups[2].Value,Context=row.Groups[3].Value,Data=row.Groups[4].Value,Description=DescribeType(System.Convert.ToUInt32(row.Groups[2].Value,16)),Raw=raw});}
   if(Line(until)!="END LOG")throw new System.FormatException("日志快照未完整结束，不替换上次完整快照");
   lock(gate){boardLog=rows;logRevision++;operation="完整读取板端日志快照："+rows.Count+"条";}Add("日志快照","已读取"+rows.Count+"条；MS为板端上电毫秒，非日历时间",first);
  }
  void Process(Job j){
   if(j.Kind=="TEMPCLEAR"){
    lock(gate){if(!Recent(status)||!status.SensorInstalled){Add("拒绝","未收到有效DS18B20状态，不能解除温度锁存",null);return;}busy=true;operation="请求人工解除温度锁存";}
    string response;try{response=Command("TEMP CLEAR");}finally{lock(gate){busy=false;}}
    if(response.StartsWith("ERR ")){Add("温度解除拒绝",Policy.ErrorText(response),response);Poll();return;}
    if(response!="OK TEMP REQUEST")throw new System.FormatException("温度解除回包不匹配："+response);
    Add("温度解除请求","B板已接受人工解除请求，等待温度锁存状态确认；不自动发送STOP",response);Poll();
    lock(gate){operation=status!=null&&status.TempAlarm==0?"温度锁存已解除；退出应急仍需请求解除应急":"温度锁存尚未解除，请检查新读数或探头状态";}return;
   }
   if(j.Kind=="CONTROL"){Control(j);return;}
   if(j.Kind=="MANUAL"||j.Kind=="CLEAR"){
    if(IsManualBlocked()){Add("拒绝","自动联动开启且板端处于应急，普通字幕/手动清除不能覆盖联动通知；可明确关闭联动后操作",null);return;}
    lock(gate){if(!Recent(status)||status.Link!=1){Add("拒绝","状态过期或双板离线，暂不发送字幕",null);return;}} CaptionImage prepared=null;
    if(j.Kind=="MANUAL"){
     try{prepared=SubtitleCodec.Raster(j.Text);}
     catch(System.Exception ex){Add("输入错误",ex.Message,null);return;}
    }
    Upload(j.Text,j.Kind=="CLEAR",prepared);lock(gate){systemOwned=false;systemOwnedNonEmergency=false;lastAuto=null;operation="字幕已收到A板VS提交确认（非HDMI实测）";}Add("手动字幕",j.Kind=="CLEAR"?"已清除，恢复原字幕":j.Text,null);Poll();return;
   }
   if(j.Kind=="LOG"){ReadBoardLog();Poll();return;}
   if(j.Kind=="LOGCLEAR"){string line=Command("LOG CLEAR");if(line.StartsWith("ERR ")){Add("日志拒绝",Policy.ErrorText(line),line);return;}if(line!="OK LOG CLEARED")throw new System.FormatException("日志清除回包不匹配："+line);lock(gate){boardLog.Clear();logRevision++;}Add("板端日志清除","已清除板端日志；电脑操作记录仍保留",line);Poll();}
  }
  void Run(){
   try{io.Open();lock(gate){operation="串口已打开，正在核对PING/STATUS";}string pong=Command("PING");if(pong!="PONG")throw new System.FormatException("PING回包不匹配");Poll();lock(gate){connected=true;operation="串口协议就绪；实际双板状态见LINK";action="未发送控制请求";}Add("连接","串口PING及完整状态有效；不代表双板或HDMI已验收",null);
    while(!stop){Job c=TakeControl();if(c!=null){if(c.Kind=="TEMPCLEAR")Process(c);else Control(c);continue;}if(clock.ElapsedMilliseconds>=nextPoll)Poll();AutoPublish();if(stop)break;Job j=Take();if(j!=null)Process(j);else System.Threading.Thread.Sleep(15);}Add("断开","主动断开串口；没有发送STOP或清除，FPGA独立运行",null);
   }catch(System.OperationCanceledException){Add("断开","主动断开串口；没有发送STOP或清除，FPGA独立运行",null);}
   catch(System.Exception ex){lock(gate){lastError=ex.Message;failureKind=ex is System.UnauthorizedAccessException?"ACCESS":ex is System.IO.IOException?"IO":ex is System.TimeoutException?"TIMEOUT":"PROTOCOL";}Add("连接故障",ex.Message+"；当前状态失效，未自动重发控制命令；显示器可能仍保留最后字幕",null);}
   finally{lock(gate){connected=false;busy=false;status=null;jobs.Clear();EndDrill("连接中断，计时中断");operation="串口已断开，状态未知";}try{if(io.IsOpen)io.Close();}catch{}try{io.Dispose();}catch{}}
  }
  public BoardRecord[] BoardLog(){lock(gate){return boardLog.ToArray();}}
  static string Csv(string v){v=v??"";if(v.Length>0&&"=+-@\t\r".IndexOf(v[0])>=0)v="'"+v;return "\""+v.Replace("\"","\"\"")+"\"";}
  public void ExportAudit(string path){AuditRecord[] rows;lock(gate){rows=audit.ToArray();}var lines=new System.Collections.Generic.List<string>();lines.Add("电脑接收时间,电脑会话毫秒,类别,内容,板端原始响应");foreach(var r in rows)lines.Add(Csv(r.ReceivedAt)+","+Csv(r.Elapsed)+","+Csv(r.Kind)+","+Csv(r.Text)+","+Csv(r.Raw));System.IO.File.WriteAllLines(path,lines,new System.Text.UTF8Encoding(true));}
  public void ExportBoardLog(string path){var lines=new System.Collections.Generic.List<string>();lines.Add("电脑快照接收时间,板端上电毫秒,类型HEX,上下文HEX,数据HEX,说明,原始记录");foreach(var r in BoardLog())lines.Add(Csv(r.ReceivedAt)+","+Csv(r.Ms)+","+Csv(r.Type)+","+Csv(r.Context)+","+Csv(r.Data)+","+Csv(r.Description)+","+Csv(r.Raw));System.IO.File.WriteAllLines(path,lines,new System.Text.UTF8Encoding(true));}
 }
}
