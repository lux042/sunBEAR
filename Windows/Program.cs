namespace SunBear;
internal static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        if(args.Length>0 && args[0]=="--test")return SelfTests.Run(args.Skip(1).FirstOrDefault());
        ApplicationConfiguration.Initialize();
        var root=GetArgument(args,"--data-dir")??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"sunBEAR");
        using var mutex=new Mutex(true,"Local\\sunBEAR-"+Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(Path.GetFullPath(root)))),out var created);
        if(!created){MessageBox.Show("sunBEAR is already running with this library.","sunBEAR");return 1;}
        try{var store=new LibraryStore(root);Application.Run(new MainForm(store,store.Load(),GetArgument(args,"--smoke-test"),GetArgument(args,"--render-test")));return 0;}
        catch(Exception e){MessageBox.Show("sunBEAR could not start. Your library has not been replaced.\n\n"+e.Message,"sunBEAR",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}
    }
    static string? GetArgument(string[] args,string key){var i=Array.IndexOf(args,key);return i>=0 && i+1<args.Length?args[i+1]:null;}
}
