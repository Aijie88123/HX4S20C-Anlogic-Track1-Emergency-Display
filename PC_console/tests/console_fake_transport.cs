namespace ConsoleTests {
 public sealed class FakeTransport : EmergencyConsole.ITransport {
  readonly object gate=new object();readonly System.Collections.Generic.Queue<byte> response=new System.Collections.Generic.Queue<byte>();
  public readonly System.Collections.Generic.List<string> Commands=new System.Collections.Generic.List<string>();public readonly System.Collections.Generic.List<string> Trace=new System.Collections.Generic.List<string>();public readonly System.Collections.Generic.List<string> WireFrames=new System.Collections.Generic.List<string>();
  public bool IsOpen {get;private set;}public bool Disposed;public int ReadDelayMs=0,WriteDelayMs=0;public bool BadBinaryCrc,DropControl,MalformedLog;public int CommitCount,ClearCount;public bool ThreadSafe=true;int owner;int nextBlock=-1;byte uploadTag;byte[] bitmap=new byte[2048];
  public string StatusLine="MS=0x00000010 REQ=0 ACT=0 BAR=0 APPLY=0 ACK=1 SRC=0 LINK=1 PHY=1 CACHE=FF FAULT=0 FRESH=0 AGE=0xFFFFFFFF EXIT=0 CLOSED=0000 ROUTE=0000 REV=0000 LOG=03 LOST=0000 RXERR=0000 SENSOR=NONE";
  public void Set(string line){lock(gate){StatusLine=line;}}
  public string[] CommandSnapshot(){lock(gate){return Commands.ToArray();}}public string[] TraceSnapshot(){lock(gate){return Trace.ToArray();}}public string[] Frames(){lock(gate){return WireFrames.ToArray();}}
  public void Open(){IsOpen=true;}public void Close(){IsOpen=false;}public void Dispose(){Disposed=true;}
  static ushort Crc(byte[] a,int count){int c=65535;for(int i=0;i<count;i++){c^=a[i]<<8;for(int b=0;b<8;b++)c=((c&32768)!=0?((c<<1)^0x1021):(c<<1))&65535;}return (ushort)c;}
  void Reply(string s){foreach(byte b in System.Text.Encoding.ASCII.GetBytes(s+"\r\n"))response.Enqueue(b);}
  public void Write(byte[] a,int offset,int count){lock(gate){int tid=System.Threading.Thread.CurrentThread.ManagedThreadId;if(owner==0)owner=tid;if(tid!=owner){ThreadSafe=false;throw new System.Exception("multiple serial owners");}
   if(count==33&&a[offset]==27){if(WriteDelayMs>0)System.Threading.Thread.Sleep(WriteDelayMs);byte[] f=new byte[33];System.Array.Copy(a,offset,f,0,33);WireFrames.Add(System.BitConverter.ToString(f));byte[] p=new byte[28];System.Array.Copy(f,3,p,0,28);if(Crc(p,28)!=(f[31]|f[32]<<8)||p[0]!=18||p[1]!=1||p[24]!=49||p[25]!=66||p[26]!=85||p[27]!=83)throw new System.Exception("wire frame malformed");int index=p[4]|p[5]<<8;
    Trace.Add("B"+p[2]+":"+index);
    if(p[2]==0){if(nextBlock>=0)throw new System.Exception("overlapping uploads");nextBlock=0;uploadTag=p[3];}
    else if(p[2]==1){if(nextBlock!=index||p[3]!=uploadTag)throw new System.Exception("upload block mismatch");System.Array.Copy(p,8,bitmap,index*16,16);nextBlock++;}
    else if(p[2]==2){if(nextBlock!=128||index!=128||Crc(bitmap,2048)!=(p[6]|p[7]<<8))throw new System.Exception("full image mismatch");nextBlock=-1;CommitCount++;}
    else if(p[2]==3){if(nextBlock>=0)throw new System.Exception("clear interleaved upload");ClearCount++;}
    byte[] r=new byte[]{27,65,1,p[3],p[2],p[4],p[5],0,0,0};ushort crc=Crc(r,8);r[8]=(byte)crc;r[9]=(byte)(crc>>8);if(BadBinaryCrc){r[9]^=1;BadBinaryCrc=false;}foreach(byte b in r)response.Enqueue(b);return;
   }
   if(nextBlock>=0)throw new System.Exception("ASCII interleaved into bitmap upload");string command=System.Text.Encoding.ASCII.GetString(a,offset,count);if(!command.EndsWith("\r\n"))throw new System.Exception("bad command ending");command=command.TrimEnd('\r','\n');Commands.Add(command);Trace.Add(command);
   if(command=="PING"){Reply("PONG");return;}if(command=="STATUS?"){Reply(StatusLine);return;}
   if(command=="LOG READ 64"){Reply("LOG COUNT=03");Reply("MS=0x00000001 TYPE=01 CTX=00 DATA=0000");Reply("MS=0x00000010 TYPE=10 CTX=48 DATA=0001");Reply("MS=0x00000020 TYPE=34 CTX=0A DATA=C080");Reply(MalformedLog?"TRUNCATED LOG":"END LOG");return;}
   if(command=="LOG CLEAR"){Reply("OK LOG CLEARED");return;}if(DropControl)return;
   if(command.StartsWith("BARRIER SET ")){Reply("OK REQUEST BARRIER="+command.Substring(12));return;}
   int state=command=="DEMO FIRE"?1:command=="DEMO QUAKE"?3:command=="DEMO LAB"?5:command=="DEMO DRILL"?7:0;Reply("OK REQUEST STATE="+state);
  }}
  public int Read(byte[] a,int offset,int count){if(ReadDelayMs>0)System.Threading.Thread.Sleep(ReadDelayMs);lock(gate){int n=System.Math.Min(count,System.Math.Min(response.Count,3));for(int i=0;i<n;i++)a[offset+i]=response.Dequeue();if(n==0)throw new System.TimeoutException();return n;}}
 }
 public static class Checks {
  static int assertions;static void Assert(bool b,string m){assertions++;if(!b)throw new System.Exception("ASSERT: "+m);}
  static void Wait(System.Func<bool> p,string m,int ms){var sw=System.Diagnostics.Stopwatch.StartNew();while(sw.ElapsedMilliseconds<ms){if(p())return;System.Threading.Thread.Sleep(5);}throw new System.Exception("WAIT: "+m);}
  public static string Normal(){return "MS=0x00000010 REQ=0 ACT=0 BAR=0 APPLY=0 ACK=1 SRC=0 LINK=1 PHY=1 CACHE=FF FAULT=0 FRESH=0 AGE=0xFFFFFFFF EXIT=0 CLOSED=0000 ROUTE=0000 REV=0000 LOG=03 LOST=0000 RXERR=0000 SENSOR=NONE";}
  public static string Fire(){return "MS=0x00000020 REQ=1 ACT=1 BAR=0 APPLY=1 ACK=1 SRC=1 LINK=1 PHY=1 CACHE=FF FAULT=0 FRESH=1 AGE=0x00000000 EXIT=4 CLOSED=0080 ROUTE=8010 REV=0001 LOG=06 LOST=0000 RXERR=0000 SENSOR=NONE";}
  static bool Has(EmergencyConsole.Session s,string kind,string text){foreach(var n in s.DrainNotices())if(n.Kind==kind&&n.Text.Contains(text))return true;return false;}
  public static string Run(string exportDir,string actualStatuses){
   assertions=0;int real=0;foreach(string line in System.IO.File.ReadAllLines(actualStatuses)){if(!line.StartsWith("MS="))continue;var q=EmergencyConsole.BoardStatus.Parse(line);Assert(q.Raw==line,"actual status exact");real++;}Assert(real>=10,"real RTL status fixtures");
   var fire=EmergencyConsole.BoardStatus.Parse(Fire());Assert(EmergencyConsole.Policy.Caption(fire)=="火灾应急｜推荐4号南出口，请沿绿色路线疏散。","qualified caption exact");
   foreach(string invalid in new string[]{Fire().Replace("ACK=1","ACK=0"),Fire().Replace("APPLY=1","APPLY=0"),Fire().Replace("FRESH=1","FRESH=0"),Fire().Replace("AGE=0x00000000","AGE=0x000003E8"),Fire().Replace("REQ=1","REQ=0")})Assert(!EmergencyConsole.Policy.Caption(EmergencyConsole.BoardStatus.Parse(invalid)).Contains("推荐"),"unqualified route must not recommend");
   Assert(EmergencyConsole.Policy.Caption(EmergencyConsole.BoardStatus.Parse(Fire().Replace("LINK=1","LINK=0")))==null,"offline no auto send");
   Assert(EmergencyConsole.Policy.Caption(EmergencyConsole.BoardStatus.Parse(Fire().Replace("EXIT=4","EXIT=0").Replace("ROUTE=8010","ROUTE=0000"))).Contains("暂无可用"),"no route caption");
   Assert(EmergencyConsole.BoardStatus.Parse(Normal().Replace("LOG=03","LOG=40")).Log==64,"hex count");
   foreach(string bad in new string[]{Fire()+" ACK=1",Fire().Replace("ACK=1 ",""),Fire().Replace("ACK=1","ACK=2"),Fire().Replace("EXIT=4","EXIT=5"),Fire().Replace("SENSOR=NONE","SENSOR=TEMP"),Fire().Replace("REV=0001","REV=ZZZZ")}){bool rejected=false;try{EmergencyConsole.BoardStatus.Parse(bad);}catch(System.FormatException){rejected=true;}Assert(rejected,"invalid status rejected");}
   FakeTransport f=new FakeTransport();var s=new EmergencyConsole.Session(f,35,25);s.Start();Wait(delegate{return s.ReadView().Connected;},"connect",2000);Assert(s.ReadView().Healthy,"healthy after PING status");System.Threading.Thread.Sleep(70);Assert(f.Frames().Length==0,"normal connect no destructive clear");
   s.Publish("校园通知 EXIT A");Wait(delegate{return f.CommitCount==1&&s.ReadView().Operation.Contains("VS提交确认");},"manual full upload",3000);Assert(s.ReadView().Progress==128,"progress128");Assert(f.Frames().Length==130,"manual130frames");
   s.Request("DEMO FIRE");Wait(delegate{return s.ReadView().RequestPending;},"request pending",1500);Assert(!s.ReadView().Action.Contains("已吻合"),"request is not applied");Assert(f.CommitCount==1,"unconfirmed normal no false event");
   f.Set(Fire().Replace("FRESH=1","FRESH=0").Replace("APPLY=1","APPLY=0"));Wait(delegate{return f.CommitCount>=2;},"generic pending",3000);Assert(!s.ReadView().AutoCaption.Contains("推荐"),"pending caption generic");
   f.Set(Fire());Wait(delegate{return !s.ReadView().RequestPending&&f.CommitCount>=3;},"fire applied then guide",3000);Assert(s.ReadView().AutoCaption.Contains("4号南出口"),"actual exit4");
   int before=f.CommitCount;s.Publish("不能盖住应急");Wait(delegate{return Has(s,"拒绝","普通字幕");},"manual priority protection",1500);Assert(f.CommitCount==before,"manual did not override emergency");
   s.Request("BARRIER SET 2");Wait(delegate{return s.ReadView().RequestPending;},"barrier pending even old status",1500);Assert(!s.ReadView().AutoCaption.Contains("推荐"),"accepted request invalidates old exit recommendation");
   string reroute=Fire().Replace("BAR=0","BAR=2").Replace("CLOSED=0080","CLOSED=C080").Replace("EXIT=4","EXIT=3").Replace("ROUTE=8010","ROUTE=4001");f.Set(reroute);Wait(delegate{return !s.ReadView().RequestPending&&s.ReadView().AutoCaption.Contains("3号东出口");},"reroute actual",2500);
   string noRoute=reroute.Replace("BAR=2","BAR=3").Replace("CLOSED=C080","CLOSED=F080").Replace("EXIT=3","EXIT=0").Replace("ROUTE=4001","ROUTE=0000");f.Set(noRoute);Wait(delegate{return s.ReadView().AutoCaption.Contains("暂无可用");},"no route",2000);
   s.Request("DEMO STOP");Wait(delegate{return s.ReadView().RequestPending;},"STOP requested",1500);f.Set(Fire().Replace("REQ=1","REQ=0").Replace("ACK=1","ACK=0"));Wait(delegate{return s.ReadView().Status.Req==0&&s.ReadView().Status.Act==1;},"local retained",2000);Assert(s.ReadView().RequestPending&&f.ClearCount==0,"STOP cannot claim local alarm cleared");
   f.Set(Normal().Replace("00000010","00000030"));Wait(delegate{return f.ClearCount==1&&!s.ReadView().RequestPending;},"confirmed normal auto clear",2500);System.Threading.Thread.Sleep(100);Assert(f.ClearCount==1,"no repeated clear");
   s.Request("DEMO DRILL");string drill=Fire().Replace("REQ=1","REQ=7").Replace("ACT=1","ACT=7").Replace("CLOSED=0080","CLOSED=0020").Replace("00000020","00000040");f.Set(drill);Wait(delegate{return s.ReadView().Drill.StartsWith("演练观察中");},"observed drill starts",2500);
   f.Set(drill.Replace("LINK=1","LINK=0"));Wait(delegate{return s.ReadView().Status.Link==0;},"board link offline",1500);Assert(s.ReadView().Connected&&s.ReadView().Healthy,"USB ready differs board link");Assert(s.ReadView().Drill.Contains("中断"),"offline drill interrupted");int cmds=f.CommandSnapshot().Length;s.Request("DEMO LAB");Wait(delegate{return Has(s,"拒绝","双板离线");},"offline control refused",2000);Assert(System.Array.IndexOf(f.CommandSnapshot(),"DEMO LAB")<0,"offline command not transmitted");
   f.Set(drill);Wait(delegate{return s.ReadView().Status.Link==1;},"reconnect board",1500);s.ReadLog();Wait(delegate{return s.ReadView().BoardLogCount==3;},"complete snapshot",2500);Assert(s.BoardLog()[2].Ms=="32"&&s.BoardLog()[2].Type=="34","log hex decoded");
   s.SetAutomatic(false);s.Publish("=电脑自定义字幕");Wait(delegate{return Has(s,"手动字幕","电脑自定义字幕");},"explicit manual mode",3000);
   s.Publish(new string('测',100));Wait(delegate{return Has(s,"输入错误","too wide");},"oversize does not tear serial",2000);Assert(s.ReadView().Connected,"input error connection retained");
   s.ExportAudit(System.IO.Path.Combine(exportDir,"audit.csv"));s.ExportBoardLog(System.IO.Path.Combine(exportDir,"board.csv"));string csv=System.IO.File.ReadAllText(System.IO.Path.Combine(exportDir,"audit.csv"));Assert(csv.Contains("'=电脑自定义字幕"),"CSV formula guard");
   // Queue a control behind a running upload and an earlier log request: no interleave, control first afterward.
   f.WriteDelayMs=1;s.Publish("并发发送测试");try{Wait(delegate{return s.ReadView().Busy;},"upload busy",2500);}catch{s.ExportAudit(System.IO.Path.Combine(exportDir,"busy_failure.csv"));System.IO.File.WriteAllLines(System.IO.Path.Combine(exportDir,"busy_trace.txt"),f.TraceSnapshot());throw new System.Exception("busy failed: "+s.ReadView().Operation+" running="+s.ReadView().Running+" connected="+s.ReadView().Connected);}s.ReadLog();s.Request("DEMO QUAKE");Wait(delegate{return System.Array.IndexOf(f.CommandSnapshot(),"DEMO QUAKE")>=0;},"priority control",6000);f.WriteDelayMs=0;Assert(f.ThreadSafe,"single serial owner");
   string[] trace=f.TraceSnapshot();int qi=System.Array.LastIndexOf(trace,"DEMO QUAKE");Assert(qi>0&&trace[qi-1].StartsWith("B2:")||qi>1&&trace[qi-1]=="STATUS?","control after full commit boundary");
   f.Set(Fire().Replace("MS=0x00000020","MS=0x00000001"));Wait(delegate{return Has(s,"板端重启","复位");},"board uptime reset",2000);
   s.ClearLog();Wait(delegate{return s.ReadView().BoardLogCount==0;},"log clear",2000);Assert(s.ReadView().Connected,"clear leaves control alive");
   System.IO.File.WriteAllLines(System.IO.Path.Combine(exportDir,"wire_frames.txt"),f.Frames());System.IO.File.WriteAllLines(System.IO.Path.Combine(exportDir,"transactions.txt"),f.TraceSnapshot());
   s.Dispose();Assert(f.Disposed&&!s.ReadView().Connected,"stop disposes");
   FakeTransport badf=new FakeTransport();badf.BadBinaryCrc=true;var bads=new EmergencyConsole.Session(badf,35,25);bads.Start();Wait(delegate{return bads.ReadView().Connected;},"bad test connect",1500);bads.Publish("CRC错误");Wait(delegate{return !bads.ReadView().Running;},"bad CRC closes unknown",2000);Assert(bads.ReadView().Status==null&&badf.Disposed,"bad CRC status invalid");bads.Dispose();
   FakeTransport timeout=new FakeTransport();timeout.DropControl=true;var ts=new EmergencyConsole.Session(timeout,35,25);ts.Start();Wait(delegate{return ts.ReadView().Connected;},"timeout connect",1500);ts.Request("DEMO FIRE");Wait(delegate{return !ts.ReadView().Running;},"control timeout",6000);int nfire=0;foreach(string c in timeout.CommandSnapshot())if(c=="DEMO FIRE")nfire++;Assert(nfire==1,"control timeout never retransmits");ts.Dispose();
   FakeTransport logf=new FakeTransport();var ls=new EmergencyConsole.Session(logf,35,25);ls.Start();Wait(delegate{return ls.ReadView().Connected;},"log test connect",1500);ls.ReadLog();Wait(delegate{return ls.ReadView().BoardLogCount==3;},"initial snapshot",2000);logf.MalformedLog=true;ls.ReadLog();Wait(delegate{return !ls.ReadView().Running;},"bad snapshot close",2000);Assert(ls.BoardLog().Length==3,"partial log never replaces complete snapshot");ls.Dispose();
   return "PASS: "+assertions+" assertions; actual RTL status fixtures="+real+"; serialized UART state machine, requests/actual/apply, auto priorities, stale/offline/local ownership/no-route, 130-frame uploads, log snapshots/CSV, faults and no retries";
  }
 }
}
