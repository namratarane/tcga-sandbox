/*
 * Software License, Version 1.0 Copyright 2013 SRA International, Inc. Copyright Notice.  
 * The software subject to this notice and license includes both human readable source 
 * code form and machine readable, binary, object code form (the "caBIG Software").
 *
 * Please refer to the complete License text for full details at the root of the project.
 */

package gov.nih.nci.ncicb.tcga.dcc.io.server;

import io.netty.bootstrap.ServerBootstrap;

/**
 * Extension of the {@link Server} interface that defines the behavior specific
 * to server implementations using Netty.
 * 
 * @author nichollsmc
 */
public interface NettyServer extends Server {

    /**
     * Create and return a configured {@link ServerBootstrap} instance.
     * 
     * @return configured {@link ServerBootstrap} instance
     */
    ServerBootstrap createServerBootstrap();

}
